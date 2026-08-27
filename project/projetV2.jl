### A Pluto.jl notebook ###
# v1.0.3

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ f8c48843-170d-40db-b967-c8f7a8468266
begin

    using PlutoUI
    using JSON3
    using Graphs
    using GraphPlot
    using Colors
    using HiGHS
    using JuMP
end

# ╔═╡ 98ab0dc3-24cb-4fd5-9b82-e48a8ba49e90
md"""
# JSON network → Julia graph

This Pluto notebook reads a JSON network with the same structure as the supplied file:

- `directed`
- `multigraph`
- `nodes`: each node has `id` and `name`
- `links`: each link has `id`, `from`, `to`, `metric`, and `capacity`

The graph itself is stored as a `Graphs.SimpleDiGraph` or `Graphs.SimpleGraph`.
Node and edge attributes are kept separately in a `NetworkGraph` object.
"""

# ╔═╡ 0a1de3ef-a839-41f1-8155-248d86fc01a5
md"""
## 1. Data structure

`Graphs.jl` stores the graph topology, but a `SimpleGraph`/`SimpleDiGraph` does not
directly store attributes such as `name`, `metric`, or `capacity`.

The structure below keeps all of them together.
"""

# ╔═╡ 0b81fdf8-9ccc-44c0-9b1c-9ed247dd2c30
struct NetworkGraph{G<:AbstractGraph}
    graph::G

    # One entry per Julia vertex.
    # node_data[v] = (json_id = ..., name = ...)
    node_data::Vector{NamedTuple{(:json_id, :name), Tuple{Int, String}}}

    # Translation from JSON node id to Graphs.jl vertex number.
    json_to_vertex::Dict{Int, Int}

    # Edge attributes indexed by Julia endpoints (u,v).
    edge_data::Dict{
        Tuple{Int, Int},
        NamedTuple{(:id, :metric, :capacity), Tuple{Int, Float64, Float64}}
    }
end

# ╔═╡ db49cc88-4824-486e-ac37-9d4bf950e015
md"""
## 2. Conversion function

The JSON node identifiers do not have to be consecutive or start at 0.
A dictionary explicitly maps each JSON id to a Julia vertex in `1:n`.
"""

# ╔═╡ 9318fcd7-3fef-4514-9cf9-42286065f3ec
function json_to_network(json_text::AbstractString)
    data = JSON3.read(json_text)

    hasproperty(data, :directed) ||
        error("Missing JSON field: directed")
    hasproperty(data, :multigraph) ||
        error("Missing JSON field: multigraph")
    hasproperty(data, :nodes) ||
        error("Missing JSON field: nodes")
    hasproperty(data, :links) ||
        error("Missing JSON field: links")

    Bool(data.multigraph) &&
        error("This notebook uses SimpleGraph/SimpleDiGraph and therefore does not support multigraph=true.")

    n = length(data.nodes)

    # Map JSON ids to Julia vertices 1,...,n.
    json_to_vertex = Dict{Int, Int}()
    node_data = Vector{
        NamedTuple{(:json_id, :name), Tuple{Int, String}}
    }(undef, n)

    for (v, node) in enumerate(data.nodes)
        id = Int(node.id)

        haskey(json_to_vertex, id) &&
            error("Duplicate node id in JSON: $id")

        json_to_vertex[id] = v
        node_data[v] = (
            json_id = id,
            name = String(node.name),
        )
    end

    # Directed or undirected graph according to the JSON field.
    g = Bool(data.directed) ? SimpleDiGraph(n) : SimpleGraph(n)

    edge_data = Dict{
        Tuple{Int, Int},
        NamedTuple{(:id, :metric, :capacity), Tuple{Int, Float64, Float64}}
    }()

    for link in data.links
        from_id = Int(link.from)
        to_id   = Int(link.to)

        haskey(json_to_vertex, from_id) ||
            error("Unknown node id in link: $from_id")
        haskey(json_to_vertex, to_id) ||
            error("Unknown node id in link: $to_id")

        u = json_to_vertex[from_id]
        v = json_to_vertex[to_id]

        key = Bool(data.directed) ? (u, v) : minmax(u, v)

        haskey(edge_data, key) &&
            error("Multiple links between the same endpoints are not supported when multigraph=false.")

        added = add_edge!(g, u, v)
        added ||
            error("Could not add edge ($from_id,$to_id). Check the JSON for duplicate links.")

        edge_data[key] = (
            id       = Int(link.id),
            metric   = Float64(link.metric),
            capacity = Float64(link.capacity),
        )
    end

    return NetworkGraph(g, node_data, json_to_vertex, edge_data)
end

# ╔═╡ a903bad2-beea-43ef-8f13-7de7607ef24e
function load_network_json(filename::AbstractString)
    return json_to_network(read(filename, String))
end

# ╔═╡ 9741cac2-89e9-4f9a-8cd1-ab90fe068d64
md"""
## 3. Useful access functions
"""

# ╔═╡ 73961e8f-76ed-43ba-81e3-8ec5910c8c50
begin
    json_id(net::NetworkGraph, v::Integer) =
        net.node_data[v].json_id

    node_name(net::NetworkGraph, v::Integer) =
        net.node_data[v].name

    vertex_from_json_id(net::NetworkGraph, id::Integer) =
        net.json_to_vertex[Int(id)]

    function edge_attributes(net::NetworkGraph, u::Integer, v::Integer)
        key = is_directed(net.graph) ? (Int(u), Int(v)) : minmax(Int(u), Int(v))
        return net.edge_data[key]
    end
end

# ╔═╡ 7ce3337c-2b51-4d2b-82fa-a5c039040fd2
md"""
## 4. Choose a JSON file

Use the file picker in Pluto. Any JSON file with the same format can be selected.
"""

# ╔═╡ c1ed742b-a4e5-4936-97e1-2fb037c1859a
@bind json_file FilePicker([MIME("application/json")])

# ╔═╡ 91ab1a2c-3c86-4cb4-8ae3-bc2b68f066ce
network = if ismissing(json_file) || isnothing(json_file)
    nothing
else
    json_to_network(String(json_file["data"]))
end

# ╔═╡ 023602b4-efe3-4200-b072-5a2c50dac4f8
md"""
## 5. Inspect the resulting graph
"""

# ╔═╡ 6e6b342b-ef1c-4a05-aa77-af0e8449a36d
if isnothing(network)
    "Choose a JSON file above."
else
    (
        graph_type = typeof(network.graph),
        directed = is_directed(network.graph),
        number_of_vertices = nv(network.graph),
        number_of_edges = ne(network.graph),
    )
end

# ╔═╡ 4a4401f0-5f3d-4155-93a2-3de88574320d
if isnothing(network)
    nothing
else
    [
        (
            julia_vertex = v,
            json_id = json_id(network, v),
            name = node_name(network, v),
        )
        for v in vertices(network.graph)
    ]
end

# ╔═╡ 53896b8b-5c8f-4427-8d4b-744019644260
if isnothing(network)
    nothing
else
    [
        merge(
            (
                julia_from = src(e),
                julia_to = dst(e),
                json_from = json_id(network, src(e)),
                json_to = json_id(network, dst(e)),
            ),
            edge_attributes(network, src(e), dst(e)),
        )
        for e in edges(network.graph)
    ]
end

# ╔═╡ 51ebfbbb-b167-4196-ab92-4bac51e1182b
md"""
## 6. Using the graph in Graphs.jl algorithms

The actual `Graphs.jl` graph object is:

```julia
network.graph
```

For example:

```julia
g = network.graph

outneighbors(g, 1)
inneighbors(g, 1)        # for a directed graph
has_edge(g, 1, 10)

edge_attributes(network, 1, 10)
```

If you do not want to use the Pluto file picker, you can also load a file directly:

```julia
network = load_network_json("my_network.json")
g = network.graph
```
"""

# ╔═╡ 48a8b6f1-e079-4f7d-9070-4913e50a9a69
md"""
## 7. Example of weighted information

`Graphs.jl` sees only the topology. To obtain the `metric` or `capacity` of an arc:

```julia
a = edge_attributes(network, u, v)

a.metric
a.capacity
a.id
```

For optimization models, one can also create dictionaries indexed by graph edges:

```julia
metric = Dict(
    (src(e), dst(e)) => edge_attributes(network, src(e), dst(e)).metric
    for e in edges(network.graph)
)

capacity = Dict(
    (src(e), dst(e)) => edge_attributes(network, src(e), dst(e)).capacity
    for e in edges(network.graph)
)
```
"""

# ╔═╡ e2b7e5ba-96eb-45c8-bf7a-db71e2831f43
md"""
## 8. Visualize the graph

`GraphPlot.jl` is used for a simple visualization of the network.

- vertices are labelled with their JSON names;
- directed JSON networks are shown with arrows;
- the first plot shows the complete topology;
- later, the shortest path will be highlighted.
"""

# ╔═╡ da7c084f-5af9-4a41-a440-0db019af2932
function graph_plot(
    net::NetworkGraph;
    paths::Vector{Vector{Int}} = Vector{Vector{Int}}(),
)
    g = net.graph
    E = collect(edges(g))

    node_labels = [node_name(net, v) for v in vertices(g)]

    # Vertices and arcs belonging to at least one shortest path.
    path_vertices = Set{Int}()
    path_edges = Set{Tuple{Int, Int}}()

    for path in paths
        union!(path_vertices, path)

        for i in 1:(length(path) - 1)
            u, v = path[i], path[i + 1]
            key = is_directed(g) ? (u, v) : minmax(u, v)
            push!(path_edges, key)
        end
    end

    node_colors = [
        v in path_vertices ? colorant"orange" : colorant"lightskyblue"
        for v in vertices(g)
    ]

    edge_colors = [
        begin
            key = is_directed(g) ? (src(e), dst(e)) : minmax(src(e), dst(e))
            key in path_edges ? colorant"red" : colorant"lightgray"
        end
        for e in E
    ]

    edge_widths = [
        begin
            key = is_directed(g) ? (src(e), dst(e)) : minmax(src(e), dst(e))
            key in path_edges ? 4.0 : 1.0
        end
        for e in E
    ]

    # Metric labels are displayed only on arcs belonging to
    # at least one shortest path.
    edge_labels = [
        begin
            key = is_directed(g) ? (src(e), dst(e)) : minmax(src(e), dst(e))
            key in path_edges ?
                string(edge_attributes(net, src(e), dst(e)).metric) :
                ""
        end
        for e in E
    ]

    return gplot(
        g,
        nodelabel = node_labels,
        nodefillc = node_colors,
        edgestrokec = edge_colors,
        edgelinewidth = edge_widths,
        edgelabel = edge_labels,
        arrowlengthfrac = is_directed(g) ? 0.08 : 0.0,
    )
end

# ╔═╡ ca1a8a38-29da-4131-bf28-1ccc383b010e
if isnothing(network)
    nothing
else
    graph_plot(network)
end

# ╔═╡ 1dcb054f-4d62-495f-ad14-709a0f15561b
md"""
## 9. Metric matrix for shortest paths

`Graphs.dijkstra_shortest_paths` accepts a distance matrix.

For every arc `(u,v)` we set

```julia
D[u,v] = metric(u,v)
```

and all non-existing arcs have weight `Inf`.
"""

# ╔═╡ d303ccb2-b446-4949-b4da-f293a90b40d6
function metric_matrix(net::NetworkGraph)
    g = net.graph
    n = nv(g)

    D = fill(Inf, n, n)

    for v in vertices(g)
        D[v, v] = 0.0
    end

    for e in edges(g)
        u, v = src(e), dst(e)
        w = edge_attributes(net, u, v).metric

        w < 0 &&
            error("Dijkstra's algorithm requires non-negative metric values.")

        D[u, v] = w

        if !is_directed(g)
            D[v, u] = w
        end
    end

    return D
end

# ╔═╡ dda07fae-f8e0-49fa-b4ca-4974425cf7f7
md"""
## 10. Choose the source and destination

The menus display the node names and JSON ids.
The selected values are JSON ids; the conversion to Julia vertex numbers is automatic.
"""

# ╔═╡ b12c2578-ed86-4107-b14b-73df424744a2
vertex_options = if isnothing(network)
    [0 => "Load a JSON file first"]
else
    [
        json_id(network, v) =>
            "$(node_name(network, v))  [JSON id=$(json_id(network, v))]"
        for v in vertices(network.graph)
    ]
end

# ╔═╡ 851cdb44-c893-4f37-a0e4-2c5c87934210
md"""
Source vertex: $(@bind source_json_id Select(vertex_options))
"""

# ╔═╡ f93544da-3607-4b2d-9072-6a85dbeb45bc
md"""
Destination vertex: $(@bind target_json_id Select(reverse(vertex_options)))
"""

# ╔═╡ 5f053ac7-08d8-4369-8b13-e086ba4c72cb
md"""
## 11. All shortest paths using Dijkstra and `metric`

Calling

```julia
dijkstra_shortest_paths(g, s, D; allpaths = true)
```

asks `Graphs.jl` to keep **all shortest-path predecessors**, not only one parent.

We then backtrack through `state.predecessors` to enumerate every shortest
path from the selected source to the selected destination.
"""

# ╔═╡ 6df15930-a355-46c3-a3a7-2fb46d4eea0b
function enumerate_all_shortest_paths(
    state,
    source::Integer,
    target::Integer,
)
    # No path from source to target.
    isfinite(state.dists[target]) ||
        return Vector{Vector{Int}}()

    paths = Vector{Vector{Int}}()
    reverse_path = Int[target]

    function backtrack(v::Int)
        if v == source
            push!(paths, reverse(copy(reverse_path)))
            return
        end

        for p in state.predecessors[v]
            p == 0 && continue

            # This guard prevents recursion loops if a graph contains
            # zero-metric cycles.
            p in reverse_path && continue

            push!(reverse_path, p)
            backtrack(p)
            pop!(reverse_path)
        end
    end

    backtrack(Int(target))
    return paths
end

# ╔═╡ 4b827fab-43e4-4ac2-9804-bf67d3ecfd85
function all_shortest_paths_metric(
    net::NetworkGraph,
    source_json_id::Integer,
    target_json_id::Integer,
)
    g = net.graph

    s = vertex_from_json_id(net, source_json_id)
    t = vertex_from_json_id(net, target_json_id)

    D = metric_matrix(net)

    # allpaths=true tells Dijkstra to retain every optimal predecessor.
    state = dijkstra_shortest_paths(
        g,
        s,
        D;
        allpaths = true,
    )

    paths = enumerate_all_shortest_paths(state, s, t)

    return (
        source = s,
        target = t,
        distance = state.dists[t],
        number_of_paths = length(paths),
        dijkstra_pathcount = state.pathcounts[t],
        paths = paths,
    )
end

# ╔═╡ 96a99b99-d798-4289-909f-5ad32a6684fb
shortest = if isnothing(network)
    nothing
else
    all_shortest_paths_metric(
        network,
        source_json_id,
        target_json_id,
    )
end

# ╔═╡ 5228b6a0-27c2-4a6b-b3fd-e8e32bbc8a0c
if isnothing(shortest)
    nothing
elseif isempty(shortest.paths)
    "There is no directed path between the selected vertices."
else
    (
        source_json_id = source_json_id,
        target_json_id = target_json_id,
        shortest_distance = shortest.distance,
        number_of_shortest_paths = shortest.number_of_paths,
        paths = [
            (
                path_number = k,
                julia_vertices = path,
                json_ids = [
                    json_id(network, v)
                    for v in path
                ],
                names = [
                    node_name(network, v)
                    for v in path
                ],
            )
            for (k, path) in enumerate(shortest.paths)
        ],
    )
end

# ╔═╡ 8ada81cb-bbe3-43d7-a415-5f123e5e85b3
md"""
### Arc-by-arc description of every shortest path
"""

# ╔═╡ c00f5357-7fa4-44e5-907d-37f6baf1dfcb
if isnothing(shortest) || isempty(shortest.paths)
    nothing
else
    [
        (
            path_number = k,
            total_metric = shortest.distance,
            arcs = [
                (
                    from = node_name(network, path[i]),
                    to = node_name(network, path[i + 1]),
                    metric = edge_attributes(
                        network,
                        path[i],
                        path[i + 1],
                    ).metric,
                )
                for i in 1:(length(path) - 1)
            ],
        )
        for (k, path) in enumerate(shortest.paths)
    ]
end

# ╔═╡ e0b1bd48-3090-4241-a22d-4d76b6be49fd
md"""
## 12. Visualize all shortest paths

Every arc belonging to **at least one shortest path** is shown in red.
Every vertex belonging to at least one shortest path is shown in orange.

If several shortest paths share an arc, that arc is drawn only once.
"""

# ╔═╡ c4c1b5ea-87f8-4b26-b9d7-4bdab86d11f4
if isnothing(shortest) || isempty(shortest.paths)
    nothing
else
    graph_plot(network; paths = shortest.paths)
end

# ╔═╡ 3845923b-4490-4c23-91c6-690c5f0d5726
md"""
### Direct programmatic use

Without the Pluto menus:

```julia
network = load_network_json("my_network.json")

result = all_shortest_paths_metric(network, 0, 14)

result.distance
result.number_of_paths
result.paths
```

For example,

```julia
for (k, path) in enumerate(result.paths)
    println("Shortest path ", k, ": ", path)
end
```

The arguments `0` and `14` are JSON node ids, not Julia vertex numbers.

### Important distinction

This computes **all paths having the minimum `metric` value between one
selected source and one selected destination**.

It is different from computing one shortest path for every pair of vertices.
"""

# ╔═╡ 77777777-7777-7777-7777-777777777777
begin
    # Helper portable pour localiser les fichiers JSON
    function find_file(filename::AbstractString)
        for p in [filename, joinpath("setA", filename), joinpath(@__DIR__, filename), joinpath(@__DIR__, "setA", filename)]
            if isfile(p)
                return p
            end
        end
        return filename
    end

    # STEP 1 : Chargement des fichiers
    function FetchFiles(NetName, ScenarioName, TmName)
        return load_network_json(find_file(NetName)), JSON3.parsefile(find_file(ScenarioName)), JSON3.parsefile(find_file(TmName))
    end

    network_s4, scenario_s4, tm_s4 = FetchFiles("setA-02-net.json", "setA-02-scenario.json", "setA-02-tm.json")

    # STEP 2 : Plus courts chemins et proportions d'ecoulement r(i, j, a)
    function all_pairs_shortest_data(g, distmx)
        n = nv(g)
        d = fill(Inf, n, n)
        sigma = zeros(Float64, n, n)
        for i in vertices(g)
            state = dijkstra_shortest_paths(g, i, distmx; allpaths = true)
            d[i, :] .= state.dists
            sigma[i, :] .= state.pathcounts
        end
        return d, sigma
    end

    function compute_r_t(g, distmx)
        n = nv(g)
        d, sigma = all_pairs_shortest_data(g, distmx)
        r = Dict{Tuple{Int, Int, Int, Int}, Float64}()
        for i in 1:n
            for j in 1:n
                if i == j
                    continue
                end
                for edge in edges(g)
                    u = src(edge)
                    v = dst(edge)
                    c_a = distmx[u, v]
                    if isapprox(d[i, u] + c_a + d[v, j], d[i, j]; atol=1e-9) && sigma[i, j] != 0
                        r[i, j, u, v] = (sigma[i, u] * sigma[v, j]) / sigma[i, j]
                    else
                        r[i, j, u, v] = 0.0
                    end
                end
            end
        end
        return r
    end

    # STEP 3 : Donnees et conversion indispensable des identifiants JSON
    C_mat = metric_matrix(network_s4)
    V_nodes = nv(network_s4.graph)
    MaxSeg = scenario_s4.max_segments
    list_edge = JSON3.parsefile(find_file("setA-02-net.json")).links

    # Correction cle : Les identifiants s et t dans tm.json (0..29) sont convertis en 1..30
    Demands = [
        (
            s = network_s4.json_to_vertex[Int(d.s)],
            t = network_s4.json_to_vertex[Int(d.t)],
            v = Float64.(d.v)
        )
        for d in tm_s4.demands
    ]

    r_coeffs = compute_r_t(network_s4.graph, C_mat)

    # STEP 4 : Modele JuMP et resolution HiGHS
    model = Model(HiGHS.Optimizer)
    set_silent(model)

    @variable(model, lambdaPrime >= 0)
    @variable(model, x[i=1:V_nodes, j=1:V_nodes, d in Demands; i != j], Bin)
    @variable(model, lambda[a in list_edge] >= 0)

    # Borne sur le nombre maximal de segments
    @constraint(model, [d in Demands], sum(x[i, j, d] for i=1:V_nodes, j=1:V_nodes if j != i) <= MaxSeg)

    # Conservation de flot (100% faisable car d.s et d.t sont dans 1:V_nodes)
    @constraint(model, [i=1:V_nodes, d in Demands; i == d.s], sum(x[i, j, d] - x[j, i, d] for j=1:V_nodes if j != i) == 1)
    @constraint(model, [i=1:V_nodes, d in Demands; i == d.t], sum(x[i, j, d] - x[j, i, d] for j=1:V_nodes if j != i) == -1)
    @constraint(model, [i=1:V_nodes, d in Demands; i != d.s && i != d.t], sum(x[i, j, d] - x[j, i, d] for j=1:V_nodes if j != i) == 0)

    # Contraintes de capacite des arcs securisees
    for a in list_edge
        u_edge = network_s4.json_to_vertex[Int(a.from)]
        v_edge = network_s4.json_to_vertex[Int(a.to)]
        cap_a = Float64(a.capacity)
        @constraint(model,
            sum(get(r_coeffs, (i, j, u_edge, v_edge), 0.0) * d.v[1] * x[i, j, d]
                for i=1:V_nodes, j=1:V_nodes, d in Demands if j != i
            ) <= lambda[a] * cap_a
        )
    end

    # Linearisation Minimax
    @constraint(model, [a in list_edge], lambdaPrime >= lambda[a])

    # Objectif
    @objective(model, Min, lambdaPrime)

    # Optimisation unique
    set_optimizer_attribute(model, "time_limit", 60.0)
    cpu_time = @elapsed optimize!(model)
    solve_status = termination_status(model)

    # Affichage du resultat
    (
        statut = solve_status,
        mlu_optimal = has_values(model) ? round(objective_value(model), digits=4) : Inf,
        temps_cpu_secondes = round(cpu_time, digits=3)
    )
end


# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
Colors = "5ae59095-9a9b-59fe-a467-6f913c188581"
GraphPlot = "a2cc645c-3eea-5389-862e-a155d0052231"
Graphs = "86223c79-3864-5bf0-83f7-82e725a168b6"
HiGHS = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
JSON3 = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
JuMP = "4076af6c-e467-56ae-b986-b466b2749572"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"

[compat]
Colors = "~0.13.1"
GraphPlot = "~0.6.2"
Graphs = "~1.14.0"
HiGHS = "~1.24.1"
JSON3 = "~1.14.3"
JuMP = "~1.31.2"
PlutoUI = "~0.7.83"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.12.7"
manifest_format = "2.0"
project_hash = "83a96683889af5139d2dfff339ddf9158ae5cffe"

[[deps.AbstractPlutoDingetjes]]
git-tree-sha1 = "6c3913f4e9bdf6ba3c08041a446fb1332716cbc2"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.4.0"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.2"

[[deps.ArnoldiMethod]]
deps = ["LinearAlgebra", "Random", "StaticArrays"]
git-tree-sha1 = "d57bd3762d308bded22c3b82d033bff85f6195c6"
uuid = "ec485272-7323-5ecc-a04f-4719b315124d"
version = "0.4.0"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"
version = "1.11.0"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"
version = "1.11.0"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "1b96ea4a01afe0ea4090c5c8039690672dd13f2e"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.9+0"

[[deps.CodecBzip2]]
deps = ["Bzip2_jll", "TranscodingStreams"]
git-tree-sha1 = "84990fa864b7f2b4901901ca12736e45ee79068c"
uuid = "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
version = "0.8.5"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "970758a3d591a2a5c2a907c53f2e2f8c1b1d3537"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.9"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "67e11ee83a43eb71ddc950302c53bf33f0690dfe"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.12.1"
weakdeps = ["StyledStrings"]

    [deps.ColorTypes.extensions]
    StyledStringsExt = "StyledStrings"

[[deps.Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "37ea44092930b1811e666c3bc38065d7d87fcc74"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.13.1"

[[deps.CommonSubexpressions]]
deps = ["MacroTools"]
git-tree-sha1 = "cda2cfaebb4be89c9084adaca7dd7333369715c5"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.1"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.3.1+2"

[[deps.Compose]]
deps = ["Base64", "Colors", "DataStructures", "Dates", "IterTools", "JSON", "LinearAlgebra", "Measures", "Printf", "Random", "Requires", "Statistics", "UUIDs"]
git-tree-sha1 = "d75431a71f82758e218779ccb3369f3243fd2bc1"
uuid = "a81c6b42-2e10-5240-aca2-a61377ecd94b"
version = "0.9.7"

[[deps.DataStructures]]
deps = ["OrderedCollections"]
git-tree-sha1 = "b0bc6d2cad1fed8b7fd59a1551a991cb3d2809e6"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.19.6"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
version = "1.11.0"

[[deps.DelimitedFiles]]
deps = ["Mmap"]
git-tree-sha1 = "9e2f36d3c96a820c678f2f1f1782582fcf685bae"
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"
version = "1.9.1"

[[deps.DiffResults]]
deps = ["StaticArraysCore"]
git-tree-sha1 = "782dd5f4561f5d267313f23853baaaa4c52ea621"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.1.0"

[[deps.DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "79a2aca180a85c690c58a020d47b426954b590f8"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.16.0"

[[deps.DocStringExtensions]]
git-tree-sha1 = "7442a5dfe1ebb773c29cc2962a8980f47221d76c"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.5"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.7.0"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"
version = "1.11.0"

[[deps.FixedPointNumbers]]
deps = ["Random", "Statistics"]
git-tree-sha1 = "59af96b98217c6ef4ae0dfe065ac7c20831d1a84"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.6"

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions"]
git-tree-sha1 = "1b86cca764a61dcac4fef4c5e16e378e5ed6953c"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "1.4.5"
weakdeps = ["StaticArrays"]

    [deps.ForwardDiff.extensions]
    ForwardDiffStaticArraysExt = "StaticArrays"

[[deps.GraphPlot]]
deps = ["ArnoldiMethod", "Colors", "Compose", "DelimitedFiles", "Graphs", "LinearAlgebra", "Random", "SparseArrays"]
git-tree-sha1 = "066c87e33a8fcc3518c9e9970a1cbf85aa79fd6c"
uuid = "a2cc645c-3eea-5389-862e-a155d0052231"
version = "0.6.2"

[[deps.Graphs]]
deps = ["ArnoldiMethod", "DataStructures", "Inflate", "LinearAlgebra", "Random", "SimpleTraits", "SparseArrays", "Statistics"]
git-tree-sha1 = "7eb45fe833a5b7c51cf6d89c5a841d5967e44be3"
uuid = "86223c79-3864-5bf0-83f7-82e725a168b6"
version = "1.14.0"

    [deps.Graphs.extensions]
    GraphsSharedArraysExt = "SharedArrays"

    [deps.Graphs.weakdeps]
    Distributed = "8ba89e20-285c-5b6f-9357-94700520ee1b"
    SharedArrays = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[deps.HiGHS]]
deps = ["HiGHS_jll", "LinearAlgebra", "MathOptIIS", "MathOptInterface", "OpenBLAS32_jll", "PrecompileTools", "SparseArrays"]
git-tree-sha1 = "01a5241985559c08a5baadbcebd6d87daaf84a84"
uuid = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
version = "1.24.1"

[[deps.HiGHS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Zlib_jll", "libblastrampoline_jll"]
git-tree-sha1 = "2d9747b79d17c4320fe48048a3a768fe6d6d82de"
uuid = "8fd58aa0-07eb-5a78-9b36-339c94fd15ea"
version = "1.15.1+1"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "179267cfa5e712760cd43dcae385d7ea90cc25a4"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.5"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "d1a86724f81bcd184a38fd284ce183ec067d71a0"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "1.0.0"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "0ee181ec08df7d7c911901ea38baf16f755114dc"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "1.0.0"

[[deps.Inflate]]
git-tree-sha1 = "d1b1b796e47d94588b3757fe84fbf65a5ec4a80d"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.5"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"
version = "1.11.0"

[[deps.IrrationalConstants]]
git-tree-sha1 = "b2d91fe939cae05960e760110b328288867b5758"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.6"

[[deps.IterTools]]
git-tree-sha1 = "42d5f897009e7ff2cf88db414a389e5ed1bdd023"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.10.0"

[[deps.JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7204148362dafe5fe6a273f855b8ccbe4df8173e"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.8.0"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[deps.JSON3]]
deps = ["Dates", "Mmap", "Parsers", "PrecompileTools", "StructTypes", "UUIDs"]
git-tree-sha1 = "411eccfe8aba0814ffa0fdf4860913ed09c34975"
uuid = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
version = "1.14.3"

    [deps.JSON3.extensions]
    JSON3ArrowExt = ["ArrowTypes"]

    [deps.JSON3.weakdeps]
    ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"

[[deps.JuMP]]
deps = ["LinearAlgebra", "MacroTools", "MathOptInterface", "MutableArithmetics", "OrderedCollections", "PrecompileTools", "Printf", "SparseArrays"]
git-tree-sha1 = "4f27b21df3b47e8c08a83ead049afb621b2f5b3c"
uuid = "4076af6c-e467-56ae-b986-b466b2749572"
version = "1.31.2"

    [deps.JuMP.extensions]
    JuMPDimensionalDataExt = "DimensionalData"

    [deps.JuMP.weakdeps]
    DimensionalData = "0703355e-b756-11e9-17c0-8b28908087d0"

[[deps.JuliaSyntaxHighlighting]]
deps = ["StyledStrings"]
uuid = "ac6e5ff7-fb65-4e79-a425-ec3bc9c03011"
version = "1.12.0"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "OpenSSL_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.15.0+0"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "OpenSSL_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.3+1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"
version = "1.11.0"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
version = "1.12.0"

[[deps.LogExpFunctions]]
deps = ["DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "bba2d9aa057d8f126415de240573e86a8f39d2a1"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "1.0.1"

    [deps.LogExpFunctions.extensions]
    LogExpFunctionsChainRulesCoreExt = "ChainRulesCore"
    LogExpFunctionsChangesOfVariablesExt = "ChangesOfVariables"
    LogExpFunctionsInverseFunctionsExt = "InverseFunctions"

    [deps.LogExpFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ChangesOfVariables = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"
version = "1.11.0"

[[deps.MIMEs]]
git-tree-sha1 = "c64d943587f7187e751162b3b84445bbbd79f691"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "1.1.0"

[[deps.MacroTools]]
git-tree-sha1 = "1e0228a030642014fe5cfe68c2c0a818f9e3f522"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.16"

[[deps.Markdown]]
deps = ["Base64", "JuliaSyntaxHighlighting", "StyledStrings"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"
version = "1.11.0"

[[deps.MathOptIIS]]
deps = ["MathOptInterface"]
git-tree-sha1 = "3b3d69130d8ab8c39d5fa4d30e20a8e6428c9d37"
uuid = "8c4f8055-bd93-4160-a86b-a0c04941dbff"
version = "0.2.0"

[[deps.MathOptInterface]]
deps = ["CodecBzip2", "CodecZlib", "ForwardDiff", "JSON", "LinearAlgebra", "MutableArithmetics", "NaNMath", "OrderedCollections", "PrecompileTools", "Printf", "SparseArrays", "SpecialFunctions", "Test"]
git-tree-sha1 = "d10ba577e0b5a0481fab01dfd31fb20af3326954"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "1.53.0"

    [deps.MathOptInterface.extensions]
    MathOptInterfaceBenchmarkToolsExt = "BenchmarkTools"
    MathOptInterfaceCliqueTreesExt = "CliqueTrees"

    [deps.MathOptInterface.weakdeps]
    BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
    CliqueTrees = "60701a23-6482-424a-84db-faee86b9b1f8"

[[deps.Measures]]
git-tree-sha1 = "b513cedd20d9c914783d8ad83d08120702bf2c77"
uuid = "442fdcdd-2543-5da2-b0f3-8c86c306513e"
version = "0.3.3"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"
version = "1.11.0"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2025.11.4"

[[deps.MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "dc5b2c4c111c46bc79ac4405eeb563523b39c004"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "1.8.0"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "dbd2e8cd2c1c27f0b584f6661b4309609c5a685e"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.1.4"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.3.0"

[[deps.OpenBLAS32_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "libblastrampoline_jll"]
git-tree-sha1 = "30870d0f2dc0b2dba76b10df1c58c7f018413e56"
uuid = "656ef2d0-ae68-5445-9ca0-591084a874a2"
version = "0.3.34+0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.29+0"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.7+0"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "3.5.6+0"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl"]
git-tree-sha1 = "1346c9208249809840c91b26703912dff463d335"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.6+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "05f45c2e0de6259db764adbfd2f1dc6d3f8de13c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "2.0.1"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "3de8f5e6e90ebfa8d6d1f86997d6cdcd6a912ff3"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.7"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "Downloads", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "e189d0623e7ce9c37389bac17e80aac3b0302e75"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.83"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "edbeefc7a4889f528644251bdb5fc9ab5348bc2c"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.3.4"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "8b770b60760d4451834fe79dd483e318eee709c4"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.5.2"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"
version = "1.11.0"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
version = "1.11.0"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "62389eeff14780bfe55195b7204c0d8738436d64"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.1"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"
version = "1.11.0"

[[deps.SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "7ddb0b49c109481b046972c0e4ab02b2127d6a75"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.6"

[[deps.SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
version = "1.12.0"

[[deps.SpecialFunctions]]
deps = ["IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "429071b23f4c9a13fb6582f807cc2ef454082408"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.9.0"

    [deps.SpecialFunctions.extensions]
    SpecialFunctionsChainRulesCoreExt = "ChainRulesCore"

    [deps.SpecialFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "PrecompileTools", "Random", "StaticArraysCore"]
git-tree-sha1 = "fac51faf3bb96e8bc0bf6f9f39ca4955652776bb"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.9.19"

    [deps.StaticArrays.extensions]
    StaticArraysChainRulesCoreExt = "ChainRulesCore"
    StaticArraysStatisticsExt = "Statistics"

    [deps.StaticArrays.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StaticArraysCore]]
git-tree-sha1 = "6ab403037779dae8c514bad259f32a447262455a"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.4"

[[deps.Statistics]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "ae3bb1eb3bba077cd276bc5cfc337cc65c3075c0"
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.11.1"
weakdeps = ["SparseArrays"]

    [deps.Statistics.extensions]
    SparseArraysExt = ["SparseArrays"]

[[deps.StructTypes]]
deps = ["Dates", "UUIDs"]
git-tree-sha1 = "159331b30e94d7b11379037feeb9b690950cace8"
uuid = "856f2bd8-1eba-4b0a-8007-ebc267875bd4"
version = "1.11.0"

[[deps.StyledStrings]]
uuid = "f489334b-da3d-4c2e-b8f0-e476e12c162b"
version = "1.11.0"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "7.8.3+2"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"
version = "1.11.0"

[[deps.TranscodingStreams]]
git-tree-sha1 = "0c45878dcfdcfa8480052b6ab162cdd138781742"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.11.3"

[[deps.Tricks]]
git-tree-sha1 = "311349fd1c93a31f783f977a71e8b062a57d4101"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.13"

[[deps.URIs]]
git-tree-sha1 = "908fec9df6c5de98548ead82a468c95ccf6cd263"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.7.0"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
version = "1.11.0"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"
version = "1.11.0"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.3.1+2"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.15.0+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.64.0+1"
"""

# ╔═╡ Cell order:
# ╠═f8c48843-170d-40db-b967-c8f7a8468266
# ╟─98ab0dc3-24cb-4fd5-9b82-e48a8ba49e90
# ╟─0a1de3ef-a839-41f1-8155-248d86fc01a5
# ╠═0b81fdf8-9ccc-44c0-9b1c-9ed247dd2c30
# ╟─db49cc88-4824-486e-ac37-9d4bf950e015
# ╠═9318fcd7-3fef-4514-9cf9-42286065f3ec
# ╠═a903bad2-beea-43ef-8f13-7de7607ef24e
# ╠═9741cac2-89e9-4f9a-8cd1-ab90fe068d64
# ╠═73961e8f-76ed-43ba-81e3-8ec5910c8c50
# ╟─7ce3337c-2b51-4d2b-82fa-a5c039040fd2
# ╠═c1ed742b-a4e5-4936-97e1-2fb037c1859a
# ╠═91ab1a2c-3c86-4cb4-8ae3-bc2b68f066ce
# ╠═023602b4-efe3-4200-b072-5a2c50dac4f8
# ╠═6e6b342b-ef1c-4a05-aa77-af0e8449a36d
# ╠═4a4401f0-5f3d-4155-93a2-3de88574320d
# ╠═53896b8b-5c8f-4427-8d4b-744019644260
# ╟─51ebfbbb-b167-4196-ab92-4bac51e1182b
# ╟─48a8b6f1-e079-4f7d-9070-4913e50a9a69
# ╟─e2b7e5ba-96eb-45c8-bf7a-db71e2831f43
# ╠═da7c084f-5af9-4a41-a440-0db019af2932
# ╠═ca1a8a38-29da-4131-bf28-1ccc383b010e
# ╟─1dcb054f-4d62-495f-ad14-709a0f15561b
# ╠═d303ccb2-b446-4949-b4da-f293a90b40d6
# ╟─dda07fae-f8e0-49fa-b4ca-4974425cf7f7
# ╠═b12c2578-ed86-4107-b14b-73df424744a2
# ╟─851cdb44-c893-4f37-a0e4-2c5c87934210
# ╟─f93544da-3607-4b2d-9072-6a85dbeb45bc
# ╟─5f053ac7-08d8-4369-8b13-e086ba4c72cb
# ╠═6df15930-a355-46c3-a3a7-2fb46d4eea0b
# ╠═4b827fab-43e4-4ac2-9804-bf67d3ecfd85
# ╠═96a99b99-d798-4289-909f-5ad32a6684fb
# ╠═5228b6a0-27c2-4a6b-b3fd-e8e32bbc8a0c
# ╟─8ada81cb-bbe3-43d7-a415-5f123e5e85b3
# ╠═c00f5357-7fa4-44e5-907d-37f6baf1dfcb
# ╟─e0b1bd48-3090-4241-a22d-4d76b6be49fd
# ╠═c4c1b5ea-87f8-4b26-b9d7-4bdab86d11f4
# ╠═3845923b-4490-4c23-91c6-690c5f0d5726
# ╠═77777777-7777-7777-7777-777777777777
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
