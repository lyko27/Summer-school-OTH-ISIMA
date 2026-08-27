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



#######################################################################################
#######################################################################################
#######################################################################################
#######################################################################################
#######################################################################################
#######################################################################################


#################  STEP 1 ########################

function FetchFiles(NetName, ScenarioName,TmName)
    return load_network_json(NetName), JSON3.parsefile(ScenarioName), JSON3.parsefile(TmName)
end

network, scenario, tm = FetchFiles("setA-03-net.json","setA-03-scenario.json","setA-03-tm.json") 

################   STEP 2 ########################

function all_pairs_shortest_data(g, distmx)
    n = nv(g)

    # d[i,j] = shortest-path distance from i to j
    d = fill(Inf, n, n)
    
    # sigma[i,j] = number of shortest paths from i to j
    sigma = zeros(Float64, n, n)
    
    for i in vertices(g)
        state = dijkstra_shortest_paths(
            g,
            i,
            distmx;
            allpaths = true
        )

        d[i, :] .= state.dists
        sigma[i, :] .= state.pathcounts
    
    end
    return d, sigma
end


function compute_r_t(g, distmx)
    n = nv(g)
    d, sigma = all_pairs_shortest_data(g, distmx)
    
    # Structure pour stocker r[i, j, a]
    # 'a' peut être indexé par l'arc (u, v) ou son indice dans edges(g)
    r = Dict{Tuple{Int, Int, Int, Int}, Float64}()
    
    for i in 1:n
        for j in 1:n
            # S'il n'y a pas de chemin de i à j ou si i == j
            if i == j
                continue
            end
            
            for edge in edges(g)
                u = src(edge)
                v = dst(edge)
                c_a = distmx[u, v]

                # Vérifier si l'arc (u, v) appartient à un chemin le plus court de i à j
                if  isapprox(d[i, u] + c_a + d[v, j], d[i, j]; atol=1e-9) && sigma[i,j] != 0
                    r[i, j, u,v] = (sigma[i, u] * sigma[v, j]) / sigma[i, j]
                else
                    r[i, j, u,v] = 0.0
                end
            end
        end
    end
    
    return r
end


################   STEP 3: Data & tests ########################

C = metric_matrix(network)                  # matrix of the weight of arcs   
V = nv(network.graph)                       # number of node 
MaxSeg = scenario.max_segments              # maximum number of arcs for a shortest paths
Budget = scenario.budget                    
Interventions = scenario.interventions      # programmed interventions

list_edge= JSON3.parsefile("setA-03-net.json").links

Num_time_Slots = tm.num_time_slots
Demands = tm.demands

d, sigma = all_pairs_shortest_data(network.graph, C)
r = compute_r_t(network.graph, C)                       # matrix of the value of r



function test_r(i,j,rmat)                   # tests the calculated values of r for the source i and target j
    g = network.graph
    result = isapprox(sum(rmat[i,j,i,dst(e)] for e in edges(g) if src(e) == i) , 1; atol=1e-9)                  # verifies complete emission
    result = result && isapprox(sum(rmat[i,j,src(e),j] for e in edges(g) if dst(e) == j) , 1; atol=1e-9)        # verifies complete reception 
    
    for k=1:V                   # verifies flow conservation
        if k != i && k != j
            result = result && isapprox(sum(rmat[i,j, k,dst(e)] for e in edges(g) if  src(e) == k), sum(rmat[i,j, src(e),k] for e in edges(g) if  dst(e) == k);atol=1e-9)
        end
    end
    return result
end


function test_all(rmat)                                     #  tests of r for every source and target
    result = true
    for i=1:V
        for j = 1:V
            if i !=j
                result = result && test_r(i,j, rmat)
            end
        end
    end
    return result
end


println("|V|=", nv(network.graph))
println("|E|=",ne(network.graph))
println("D=", length(Demands) )


################   STEP 4: Model ########################

begin
    model = Model(HiGHS.Optimizer)

    @variable(model, lambdaPrime >= 0)
    @variable(model, x[i=1:V,j=1:V,d in Demands; i!=j] ,Bin)        # 1 if x_ij^dt is used else 0
    @variable(model, lambda[a in list_edge] >= 0)                   # load of edges

    @constraint(model, [d in Demands] ,sum(x[i,j,d] for i=1:V, j=1:V if j!=i) <= MaxSeg)                    # constraint for the max lenght 
    
    @constraint(model, [i=1:V ,d in Demands; i == d.s+1], sum(x[i, j, d] - x[j, i, d] for j=1:V if j!=i) == 1)
    @constraint(model, [i=1:V ,d in Demands; i == d.t+1], sum(x[i, j, d] - x[j, i, d] for j=1:V if j!=i) == -1)               #conservation of flow
    @constraint(model, [i=1:V ,d in Demands; i != d.s+1 && i != d.t+1], sum(x[i, j, d] - x[j, i, d] for j=1:V if j!=i) == 0)
    
    @constraint(model, [a in list_edge], sum(r[i,j,a.from +1, a.to+1] * d.v[1] * x[i,j,d] for i=1:V ,j=1:V, d in Demands if j!= i) <= lambda[a] * a.capacity)
        # a.from et a.to sont des id de sommets donc commence à 0, or dans compute_r_t, les noeuds commencent à 1 donc +1

    @constraint(model, [a in list_edge],lambdaPrime >= lambda[a])          
                                                                                                                            # Objectif
    
    @objective(model, Min, lambdaPrime)



    set_optimizer_attribute(model, "time_limit", 60.0)
	solve_status = optimize!(model)
	cpu_time = @elapsed optimize!(model)
end


################   STEP 5: Model ########################

