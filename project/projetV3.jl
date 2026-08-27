# ==============================================================================
# PROJET ROADEF / EURO 2026 - OPTIMISATION DU ROUTAGE PAR SEGMENTS (T-ASR)
# Script Julia Standard (sans Pluto, exécutable en ligne de commande ou REPL)
# ==============================================================================

using JSON3
using Graphs
using JuMP
using HiGHS
using LinearAlgebra

# ------------------------------------------------------------------------------
# 1. Structure de donnees topologiques du reseau
# ------------------------------------------------------------------------------
struct NetworkGraph{G<:AbstractGraph}
    graph::G
    node_data::Vector{NamedTuple{(:json_id, :name), Tuple{Int, String}}}
    json_to_vertex::Dict{Int, Int}
    edge_data::Dict{Tuple{Int, Int}, NamedTuple{(:id, :metric, :capacity), Tuple{Int, Float64, Float64}}}
end

json_id(net::NetworkGraph, v::Integer) = net.node_data[v].json_id
node_name(net::NetworkGraph, v::Integer) = net.node_data[v].name
vertex_from_json_id(net::NetworkGraph, id::Integer) = net.json_to_vertex[Int(id)]

function edge_attributes(net::NetworkGraph, u::Integer, v::Integer)
    key = is_directed(net.graph) ? (Int(u), Int(v)) : minmax(Int(u), Int(v))
    return net.edge_data[key]
end

# ------------------------------------------------------------------------------
# 2. Chargement du fichier topologique (*net.json)
# ------------------------------------------------------------------------------
function load_network_json(filename::AbstractString)
    data = JSON3.read(read(filename, String))
    n = length(data.nodes)

    # Correspondance explicite des identifiants JSON (ex: 0..n-1) vers sommets Julia (1..n)
    json_to_vertex = Dict{Int, Int}()
    node_data = Vector{NamedTuple{(:json_id, :name), Tuple{Int, String}}}(undef, n)

    for (v, node) in enumerate(data.nodes)
        id = Int(node.id)
        json_to_vertex[id] = v
        node_data[v] = (json_id = id, name = String(node.name))
    end

    g = Bool(data.directed) ? SimpleDiGraph(n) : SimpleGraph(n)
    edge_data = Dict{Tuple{Int, Int}, NamedTuple{(:id, :metric, :capacity), Tuple{Int, Float64, Float64}}}()

    for link in data.links
        u = json_to_vertex[Int(link.from)]
        v = json_to_vertex[Int(link.to)]
        key = Bool(data.directed) ? (u, v) : minmax(u, v)
        add_edge!(g, u, v)
        edge_data[key] = (
            id = Int(link.id),
            metric = Float64(link.metric),
            capacity = Float64(link.capacity)
        )
    end

    return NetworkGraph(g, node_data, json_to_vertex, edge_data)
end

# ------------------------------------------------------------------------------
# 3. Matrice des distances metriques (nominale et avec coupures a t=1)
# ------------------------------------------------------------------------------
function metric_matrix(net::NetworkGraph)
    n = nv(net.graph)
    C = fill(Inf, n, n)
    for v in vertices(net.graph)
        C[v, v] = 0.0
    end
    for e in edges(net.graph)
        u, v = src(e), dst(e)
        C[u, v] = edge_attributes(net, u, v).metric
    end
    return C
end

function metric_matrix_at_t(net::NetworkGraph, disabled_edges::Set{Tuple{Int, Int}})
    n = nv(net.graph)
    C = fill(Inf, n, n)
    for v in vertices(net.graph)
        C[v, v] = 0.0
    end
    for e in edges(net.graph)
        u, v = src(e), dst(e)
        if !((u, v) in disabled_edges)
            C[u, v] = edge_attributes(net, u, v).metric
        end
    end
    return C
end

# ------------------------------------------------------------------------------
# 4. Calcul des plus courts chemins via Dijkstra All-Paths
# ------------------------------------------------------------------------------
function all_pairs_shortest_data(g::AbstractGraph, distmx::Matrix{Float64})
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

# ------------------------------------------------------------------------------
# 5. Calcul exact des split coefficients ECMP r(i, j, a, t)
# Formule officielle du sujet ROADEF et du polycopie calculating_r.pdf :
# r(i, j, u, v) = (sigma(i, u) * sigma(v, j)) / sigma(i, j)
# ------------------------------------------------------------------------------
function compute_r_t(g::AbstractGraph, distmx::Matrix{Float64})
    n = nv(g)
    d, sigma = all_pairs_shortest_data(g, distmx)
    r = Dict{Tuple{Int, Int, Edge}, Float64}()

    for i in 1:n
        for j in 1:n
            if i == j || sigma[i, j] == 0.0
                continue
            end
            for edge in edges(g)
                u, v = src(edge), dst(edge)
                c_a = distmx[u, v]
                if c_a < Inf && isapprox(d[i, u] + c_a + d[v, j], d[i, j]; atol = 1e-9)
                    val = (sigma[i, u] * sigma[v, j]) / sigma[i, j]
                    if val > 1e-9
                        r[(i, j, edge)] = val
                    end
                end
            end
        end
    end
    return r
end

# ------------------------------------------------------------------------------
# 6. Chargement des demandes (*tm.json) et du scenario (*scenario.json)
# ------------------------------------------------------------------------------
function load_traffic(tm_filepath::AbstractString, json_to_vertex::Dict{Int, Int})
    data = JSON3.read(read(tm_filepath, String))
    num_slots = Int(data.num_time_slots)

    # Conversion indispensable : les identifiants JSON sont traduits en sommets Julia 1..n
    demands = [
        (
            s = json_to_vertex[Int(d.s)],
            t = json_to_vertex[Int(d.t)],
            v = Float64.(d.v)
        )
        for d in data.demands
    ]
    return demands, num_slots
end

function load_scenario(scenario_filepath::AbstractString)
    data = JSON3.read(read(scenario_filepath, String))
    max_seg = Int(data.max_segments)
    budget_t1 = hasproperty(data, :budget) && length(data.budget) > 0 ? Int(data.budget[1].value) : 0
    interv_t1 = hasproperty(data, :interventions) && length(data.interventions) > 0 ? Int.(data.interventions[1].links) : Int[]

    return (max_segments = max_seg, budget_t1 = budget_t1, interventions_t1 = interv_t1)
end

function find_file(filename::AbstractString)
    for path in [filename, joinpath("setA", filename), joinpath("project", "setA", filename), joinpath(@__DIR__, "setA", filename), joinpath(@__DIR__, filename)]
        if isfile(path)
            return path
        end
    end
    error("Fichier introuvable : $filename")
end

function build_instance_data(instance_name::String)
    net_path = find_file("$(instance_name)-net.json")
    tm_path = find_file("$(instance_name)-tm.json")
    scen_path = find_file("$(instance_name)-scenario.json")

    net = load_network_json(net_path)
    demands, num_time_slots = load_traffic(tm_path, net.json_to_vertex)
    scen = load_scenario(scen_path)

    capacities = Dict{Edge, Float64}()
    for e in edges(net.graph)
        capacities[e] = edge_attributes(net, src(e), dst(e)).capacity
    end

    # Identifier les arcs physiques touches par une intervention a t=1
    disabled_edges = Set{Tuple{Int, Int}}()
    for link_id in scen.interventions_t1
        for e in edges(net.graph)
            if edge_attributes(net, src(e), dst(e)).id == link_id
                push!(disabled_edges, (src(e), dst(e)))
            end
        end
    end

    return (
        instance = instance_name,
        net = net,
        demands = demands,
        num_time_slots = num_time_slots,
        max_segments = scen.max_segments,
        budget_t1 = scen.budget_t1,
        interventions_t1 = scen.interventions_t1,
        disabled_edges = disabled_edges,
        capacities = capacities
    )
end

# ------------------------------------------------------------------------------
# 7A. Modele JuMP Mono-Periode (t = 0 nominal, Step 4 du cours)
# ------------------------------------------------------------------------------
function solve_t_asr_single_slot(data; time_limit::Float64 = 60.0)
    net = data.net
    g = net.graph
    n_nodes = nv(g)
    V = 1:n_nodes
    demands = data.demands
    n_dem = length(demands)
    D = 1:n_dem

    println("  - Calcul des proportions r(0) a t=0...")
    C_0 = metric_matrix(net)
    r_0 = compute_r_t(g, C_0)

    println("  - Construction du modele JuMP (Nominal t=0)...")
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, time_limit)

    @variable(model, x0[k in D, i in V, j in V; i != j], Bin)
    @variable(model, lambda_max >= 0.0)

    # (1) Conservation de flot
    for k in D
        s_k = demands[k].s
        t_k = demands[k].t
        for i in V
            rhs = (i == s_k) ? 1.0 : ((i == t_k) ? -1.0 : 0.0)
            @constraint(model, sum(x0[k, i, j] for j in V if j != i) - sum(x0[k, j, i] for j in V if j != i) == rhs)
        end
    end

    # (2) Borne maxSeg
    for k in D
        @constraint(model, sum(x0[k, i, j] for i in V for j in V if i != j) <= data.max_segments)
    end

    # (3) Charge des arcs physiques et borne MLU
    for e in edges(g)
        cap_e = data.capacities[e]
        traf_0 = @expression(
            model,
            sum(
                demands[k].v[1] * get(r_0, (i, j, e), 0.0) * x0[k, i, j]
                for k in D for i in V for j in V
                if i != j && get(r_0, (i, j, e), 0.0) > 0.0
            )
        )
        @constraint(model, traf_0 <= cap_e * lambda_max)
    end

    @objective(model, Min, lambda_max)

    println("  - Optimisation par le solveur HiGHS...")
    cpu_time = @elapsed optimize!(model)
    st = termination_status(model)
    mlu = has_values(model) ? round(objective_value(model), digits = 4) : Inf

    return (
        status = st,
        mlu = mlu,
        cpu_time = round(cpu_time, digits = 3),
        x0 = has_values(model) ? value.(x0) : nothing
    )
end

# ------------------------------------------------------------------------------
# 7B. Modele JuMP Multi-Periodes (t=0 et t=1 avec Budget, Step 7 du cours)
# ------------------------------------------------------------------------------
function solve_t_asr_two_slots(data; time_limit::Float64 = 120.0)
    net = data.net
    g = net.graph
    n_nodes = nv(g)
    V = 1:n_nodes
    demands = data.demands
    n_dem = length(demands)
    D = 1:n_dem

    println("  - Calcul des proportions r(0) a t=0...")
    C_0 = metric_matrix(net)
    r_0 = compute_r_t(g, C_0)

    println("  - Calcul des proportions r(1) a t=1 (avec pannes)...")
    C_1 = metric_matrix_at_t(net, data.disabled_edges)
    r_1 = compute_r_t(g, C_1)

    println("  - Construction du modele JuMP (Couplage t=0 et t=1)...")
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, time_limit)

    @variable(model, x0[k in D, i in V, j in V; i != j], Bin)
    @variable(model, x1[k in D, i in V, j in V; i != j], Bin)
    @variable(model, z[k in D, i in V, j in V; i != j] >= 0.0)
    @variable(model, lambda_max >= 0.0)

    # (1) Conservation de flot pour t=0 et t=1
    for k in D
        s_k = demands[k].s
        t_k = demands[k].t
        for i in V
            rhs = (i == s_k) ? 1.0 : ((i == t_k) ? -1.0 : 0.0)
            @constraint(model, sum(x0[k, i, j] for j in V if j != i) - sum(x0[k, j, i] for j in V if j != i) == rhs)
            @constraint(model, sum(x1[k, i, j] for j in V if j != i) - sum(x1[k, j, i] for j in V if j != i) == rhs)
        end
    end

    # (2) Nombre maximal de segments
    for k in D
        @constraint(model, sum(x0[k, i, j] for i in V for j in V if i != j) <= data.max_segments)
        @constraint(model, sum(x1[k, i, j] for i in V for j in V if i != j) <= data.max_segments)
    end

    # (4) Linearisation de la distance de reconfiguration : |x^1 - x^0| <= z
    for k in D, i in V, j in V
        if i != j
            @constraint(model, z[k, i, j] >= x1[k, i, j] - x0[k, i, j])
            @constraint(model, z[k, i, j] >= x0[k, i, j] - x1[k, i, j])
        end
    end
    @constraint(model, sum(z[k, i, j] for k in D for i in V for j in V if i != j) <= data.budget_t1)

    # (3) Charge des arcs a t=0 et a t=1
    for e in edges(g)
        cap_e = data.capacities[e]

        traf_0 = @expression(
            model,
            sum(
                demands[k].v[1] * get(r_0, (i, j, e), 0.0) * x0[k, i, j]
                for k in D for i in V for j in V
                if i != j && get(r_0, (i, j, e), 0.0) > 0.0
            )
        )
        @constraint(model, traf_0 <= cap_e * lambda_max)

        u, v = src(e), dst(e)
        if !((u, v) in data.disabled_edges)
            v_t1_idx = length(demands[1].v) >= 2 ? 2 : 1
            traf_1 = @expression(
                model,
                sum(
                    demands[k].v[v_t1_idx] * get(r_1, (i, j, e), 0.0) * x1[k, i, j]
                    for k in D for i in V for j in V
                    if i != j && get(r_1, (i, j, e), 0.0) > 0.0
                )
            )
            @constraint(model, traf_1 <= cap_e * lambda_max)
        end
    end

    @objective(model, Min, lambda_max)

    println("  - Optimisation par le solveur HiGHS...")
    cpu_time = @elapsed optimize!(model)
    st = termination_status(model)
    mlu = has_values(model) ? round(objective_value(model), digits = 4) : Inf
    reconf = has_values(model) ? round(Int, sum(value.(z))) : 0

    return (
        status = st,
        mlu = mlu,
        reconfigurations = reconf,
        budget = data.budget_t1,
        cpu_time = round(cpu_time, digits = 3),
        x0 = has_values(model) ? value.(x0) : nothing,
        x1 = has_values(model) ? value.(x1) : nothing
    )
end

# ------------------------------------------------------------------------------
# 8. Execution Principale
# ------------------------------------------------------------------------------
function main()
    # Arguments en ligne de commande :
    # julia projetV3.jl [nom_instance] [mode: nominal | two_slots] [time_limit]
    instance_name = length(ARGS) > 0 ? ARGS[1] : "setA-01"
    mode = length(ARGS) > 1 ? ARGS[2] : "two_slots"
    time_limit = length(ARGS) > 2 ? parse(Float64, ARGS[3]) : 120.0

    println("====================================================================")
    println("  CHALLENGE ROADEF 2026 - OPTIMISATION DU ROUTAGE PAR SEGMENTS (T-ASR)")
    println("====================================================================")
    println("Instance selectionnee : ", instance_name)
    println("Mode de resolution   : ", mode == "nominal" ? "Mono-periode (t=0 nominal)" : "Multi-periodes (t=0 et t=1 avec budget)")
    println("Temps limite solveur : ", time_limit, " secondes")

    data = build_instance_data(instance_name)

    println("\nCaracteristiques de l'instance :")
    println("  - Nombre de sommets |V| : ", nv(data.net.graph))
    println("  - Nombre d'arcs    |A| : ", ne(data.net.graph))
    println("  - Nombre de demandes|D| : ", length(data.demands))
    println("  - Borne maxSeg          : ", data.max_segments)
    println("  - Budget de reconfig    : ", data.budget_t1)
    println("  - Coupures a t=1 (liens): ", collect(data.disabled_edges))

    println("\nLancement de la resolution...")
    res = if mode == "nominal"
        solve_t_asr_single_slot(data; time_limit = time_limit)
    else
        solve_t_asr_two_slots(data; time_limit = time_limit)
    end

    println("\n--------------------------------------------------------------------")
    println("RESULTATS DE L'OPTIMISATION :")
    println("--------------------------------------------------------------------")
    println("  - Statut du solveur           : ", res.status)
    println("  - Charge maximale (MLU optimal): ", res.mlu)
    if haskey(res, :reconfigurations)
        println("  - Reconfigurations effectuees : ", res.reconfigurations, " / ", res.budget, " autorisees")
    end
    println("  - Temps de calcul CPU         : ", res.cpu_time, " secondes")
    println("--------------------------------------------------------------------")

    if res.x0 !== nothing
        println("\nExemple de solution de routage pour la Demande 1 (Source ", json_id(data.net, data.demands[1].s), " -> Dest ", json_id(data.net, data.demands[1].t), ") :")
        println("  * Segments actifs a t=0 :")
        for i in vertices(data.net.graph), j in vertices(data.net.graph)
            if i != j && res.x0[1, i, j] > 0.5
                println("      Segment (", json_id(data.net, i), " -> ", json_id(data.net, j), ")")
            end
        end

        if haskey(res, :x1) && res.x1 !== nothing
            println("  * Segments actifs a t=1 :")
            for i in vertices(data.net.graph), j in vertices(data.net.graph)
                if i != j && res.x1[1, i, j] > 0.5
                    println("      Segment (", json_id(data.net, i), " -> ", json_id(data.net, j), ")")
                end
            end
        end
    end
    println("====================================================================")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
