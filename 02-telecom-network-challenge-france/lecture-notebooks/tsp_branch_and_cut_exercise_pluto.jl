### A Pluto.jl notebook ###
# v1.0.3

using Markdown
using InteractiveUtils

# ╔═╡ 75a94d33-0c45-4060-acda-4fff648f015f
begin
    using Markdown
    using InteractiveUtils
    using Graphs
    using Bonobo
    const BB = Bonobo
    using JuMP
    using HiGHS
    import MathOptInterface as MOI
end

# ╔═╡ c851df34-eada-4d39-a05c-ef27533d6ac4
begin
    using Random
    function random_euclidean_points(
        n::Int;
        L::Float64 = 100.0,
        seed::Int = 1234,
    )
        rng = MersenneTwister(seed)
    
        return [
            (
                L * rand(rng),
                L * rand(rng),
            )
            for _ in 1:n
        ]
    end
end

# ╔═╡ b88253cb-fed0-4b96-b204-982a29a15f1c
md"""
# Exercise — Branch-and-Cut for the Traveling Salesman Problem

## Objective

We consider the symmetric Traveling Salesman Problem (TSP).

The initial formulation contains:

\[
\sum_{e\in \delta(i)} x_e = 2
\qquad \forall i\in V,
\]

with

\[
0 \le x_e \le 1.
\]

The subtour elimination constraints

\[
\sum_{e\in E(S)} x_e \le |S|-1
\qquad
\forall S\subset V,\; 2\le |S|\le |V|-1
\]

are **not included initially**.

They are generated dynamically when an integer solution contains several subtours.

Bonobo is used to manage the Branch-and-Bound tree.  
The subtour-separation mechanism is implemented explicitly in `evaluate_node!`.
"""

# ╔═╡ bbee4eac-723d-478c-a0a2-911aba5e10b8
md"""
## Student task

Complete the function

```julia
find_subtours(xval, edges, n)
```

At the moment where this function is called, `xval` is an integer solution of the degree-constrained TSP formulation.

An edge `e` is considered selected when

```julia
xval[e] > 0.5
```

The function must:

1. build the undirected graph formed by the selected edges;
2. identify its connected components using a breadth-first search;
3. return the connected components as a `Vector{Vector{Int}}`.

Because every vertex has degree 2 in an integer solution satisfying the degree equations, each connected component is a cycle.

Hence:

- one connected component containing all vertices corresponds to a Hamiltonian tour;
- several connected components correspond to subtours.

Example:

```text
1 -- 2          4 -- 5
 \  /            \  /
   3               6
```

The function may return

```julia
[[1, 2, 3], [4, 5, 6]]
```

The order of components and the order of vertices inside each component do not matter.
"""

# ╔═╡ e1c84f8a-bc05-4b45-9a0d-e560fbc8face
begin
    complete_edges(n) = [(i, j) for i in 1:n-1 for j in i+1:n]

    function euclidean_instance(coords::Vector{<:Tuple})
        n = length(coords)
        edges = complete_edges(n)

        cost = [
            hypot(
                coords[i][1] - coords[j][1],
                coords[i][2] - coords[j][2],
            )
            for (i, j) in edges
        ]

        return n, edges, Float64.(cost)
    end

    const DEMO_COORDS = [
        (0.0, 0.0),
        (1.0, 0.0),
        (1.0, 1.0),
        (0.0, 1.0),
        (10.0, 0.0),
        (11.0, 0.0),
        (11.0, 1.0),
        (10.0, 1.0),
    ]
end

# ╔═╡ 5241b601-b453-4529-a22a-579c081bc33e
function find_subtours(
    xval::Vector{Float64},
    edges::Vector{Tuple{Int,Int}},
    n::Int;
    tol::Float64 = 0.5,
)
     #TODO
end

# ╔═╡ 4deefab0-4cdd-44bd-9086-b0f7bced4fd6
begin
    struct SubtourCut
        S::Vector{Int}
    end

    mutable struct TSPRoot
        n::Int
        edges::Vector{Tuple{Int,Int}}
        cost::Vector{Float64}

        global_cuts::Vector{SubtourCut}
        cut_keys::Set{Tuple}

        nodes_evaluated::Int
        lp_solves::Int
        integer_candidates::Int
        cuts_generated::Int
    end

    mutable struct TSPNode <: BB.AbstractNode
        std::BB.BnBNodeInfo

        lbs::Vector{Float64}
        ubs::Vector{Float64}

        lp_objective::Float64
        lp_solution::Vector{Float64}
        integral::Bool
    end
end

# ╔═╡ 910a5d7a-34a1-4502-9cc4-8e836e2439dd
begin
    BB.get_branching_indices(root::TSPRoot) =
        collect(eachindex(root.edges))

    BB.get_relaxed_values(
        tree::BB.BnBTree,
        node::TSPNode,
    ) = node.lp_solution
end

# ╔═╡ a4becfae-788f-42be-8873-053fdea98e04
function build_node_model(tree::BB.BnBTree, node::TSPNode)

    root = tree.root
    n = root.n
    edges = root.edges
    m = length(edges)

    model = Model(HiGHS.Optimizer)
    set_silent(model)

    @variable(
        model,
        node.lbs[e] <= x[e = 1:m] <= node.ubs[e]
    )

    # Degree equations
    for i in 1:n
        @constraint(
            model,
            sum(
                x[e]
                for e in 1:m
                if edges[e][1] == i || edges[e][2] == i
            ) == 2
        )
    end

    # Subtour elimination constraints already generated
    for cut in root.global_cuts
        S = Set(cut.S)

        @constraint(
            model,
            sum(
                x[e]
                for e in 1:m
                if edges[e][1] in S && edges[e][2] in S
            ) <= length(S) - 1
        )
    end

    @objective(
        model,
        Min,
        sum(root.cost[e] * x[e] for e in 1:m)
    )

    return model, x
end

# ╔═╡ a9f8fd69-b44d-47f9-95af-2a93a95ae23d
begin
    cut_key(S) = Tuple(sort(S))

    function add_subtour_cuts!(
        root::TSPRoot,
        subtours::Vector{Vector{Int}},
    )
        added = 0

        for S0 in subtours
            S = sort(unique(S0))

            # The full vertex set corresponds to a Hamiltonian tour
            if length(S) <= 1 || length(S) == root.n
                continue
            end

            key = cut_key(S)

            if !(key in root.cut_keys)
                push!(root.global_cuts, SubtourCut(S))
                push!(root.cut_keys, key)

                root.cuts_generated += 1
                added += 1
            end
        end

        return added
    end

    function is_integer_solution(tree::BB.BnBTree, xval)
        return all(
            BB.is_approx_feasible.(Ref(tree), xval)
        )
    end
end

# ╔═╡ dd41517c-a3c5-42aa-b99d-4b0b60af458c
function BB.evaluate_node!(tree::BB.BnBTree, node::TSPNode)

    root = tree.root
    root.nodes_evaluated += 1

    while true

        model, x = build_node_model(tree, node)
        optimize!(model)

        root.lp_solves += 1

        if termination_status(model) != MOI.OPTIMAL
            return NaN, NaN
        end

        node.lp_objective = objective_value(model)
        node.lp_solution = value.(x)

        node.integral =
            is_integer_solution(tree, node.lp_solution)

        # Fractional solution:
        # return the LP lower bound to Bonobo
        if !node.integral
            return node.lp_objective, NaN
        end

        # Integer candidate:
        # test whether it is one Hamiltonian cycle
        root.integer_candidates += 1

        subtours = find_subtours(
            node.lp_solution,
            root.edges,
            root.n,
        )

        if length(subtours) == 1 &&
           length(subtours[1]) == root.n

            return node.lp_objective,
                   node.lp_objective
        end

        # Several components:
        # add the corresponding SECs and solve this node again
        nadded = add_subtour_cuts!(root, subtours)

        if nadded == 0
            error(
                "Invalid integer candidate but no new " *
                "subtour cut was generated. Check find_subtours."
            )
        end
    end
end

# ╔═╡ 26dfc089-7d62-4133-81bd-b420fc4ac7cd
function BB.get_branching_nodes_info(
    tree::BB.BnBTree,
    node::TSPNode,
    vidx::Int,
)

    m = length(tree.root.edges)
    children = NamedTuple[]

    # Child x[vidx] = 0
    lbs0 = copy(node.lbs)
    ubs0 = copy(node.ubs)

    lbs0[vidx] = 0.0
    ubs0[vidx] = 0.0

    push!(
        children,
        (
            lbs = lbs0,
            ubs = ubs0,
            lp_objective = NaN,
            lp_solution = fill(NaN, m),
            integral = false,
        ),
    )

    # Child x[vidx] = 1
    lbs1 = copy(node.lbs)
    ubs1 = copy(node.ubs)

    lbs1[vidx] = 1.0
    ubs1[vidx] = 1.0

    push!(
        children,
        (
            lbs = lbs1,
            ubs = ubs1,
            lp_objective = NaN,
            lp_solution = fill(NaN, m),
            integral = false,
        ),
    )

    return children
end

# ╔═╡ 2b001ef4-8049-4c54-b7f4-74895407febc
function solve_tsp_branch_and_cut(
    coords = DEMO_COORDS,
)

    n, edges, cost = euclidean_instance(coords)
    m = length(edges)

    root = TSPRoot(
        n,
        edges,
        cost,
        SubtourCut[],
        Set{Tuple}(),
        0,
        0,
        0,
        0,
    )

    tree = BB.initialize(
        Node = TSPNode,
        root = root,
        sense = :Min,
        Value = Vector{Float64},
        branch_strategy = BB.MOST_INFEASIBLE(),
    )

    BB.set_root!(
        tree,
        (
            lbs = zeros(m),
            ubs = ones(m),
            lp_objective = NaN,
            lp_solution = fill(NaN, m),
            integral = false,
        ),
    )

    BB.optimize!(tree)

    xbest = BB.get_solution(tree)
    zbest = BB.get_objective_value(tree)

    selected_edges = [
        edges[e]
        for e in eachindex(edges)
        if xbest[e] > 0.5
    ]

    return (
        objective = zbest,
        x = xbest,
        selected_edges = selected_edges,
        tree = tree,
        statistics = (
            nodes_created = tree.num_nodes,
            nodes_evaluated = root.nodes_evaluated,
            lp_solves = root.lp_solves,
            integer_candidates = root.integer_candidates,
            global_subtour_cuts = root.cuts_generated,
        ),
    )
end

# ╔═╡ 198a23ce-86ea-45c2-833b-dbd89f2ec4dd


# ╔═╡ 342bc6e9-8bf5-4237-81cf-0d4d0677d023
function test_find_subtours()

    n = 6
    edges = complete_edges(n)
    xval = zeros(Float64, length(edges))

    selected = Set([
        (1, 2),
        (1, 3),
        (2, 3),
        (4, 5),
        (4, 6),
        (5, 6),
    ])

    for e in eachindex(edges)
        if edges[e] in selected
            xval[e] = 1.0
        end
    end

    subtours = find_subtours(
        xval,
        edges,
        n,
    )

    normalized =
        sort([Tuple(sort(S)) for S in subtours])

    @assert normalized ==
        [(1, 2, 3), (4, 5, 6)]

    println("find_subtours: test passed.")

    return true
end

# ╔═╡ e659ab67-09eb-4702-ab65-8359e589a6b0
md"""
## Tests

First test only the `find_subtours` routine:

```julia
test_find_subtours()
```

Then solve the complete TSP instance:

```julia
result = solve_tsp_branch_and_cut()
```

The returned object contains:

- the optimal objective value;
- the selected tour edges;
- the Branch-and-Bound tree;
- the number of nodes, LP solves, integer candidates and generated subtour cuts.
"""

# ╔═╡ 1d1870e8-0fac-4b7b-a2a4-3c8e9b9778d2
test_find_subtours()

# ╔═╡ 1c7a2307-41c9-4d57-b6f9-9ab7f171c5e5
function solve_random_tsp(
    n::Int;
    L::Float64 = 100.0,
    seed::Int = 1234,
)
    coords = random_euclidean_points(
        n;
        L = L,
        seed = seed,
    )

    result = solve_tsp_branch_and_cut(coords)

    return (
        coords = coords,
        result = result,
    )
end

# ╔═╡ 3b4671ab-2453-4686-8328-6f9e9be443e8
begin
    experiment = solve_random_tsp(
        20;
        seed = 42,
    )
    
    begin
        println("Objective      = ", experiment.result.objective)
        println("Selected edges = ", experiment.result.selected_edges)
        println("Statistics     = ", experiment.result.statistics)
    end
end

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
Bonobo = "f7b14807-3d4d-461a-888a-05dd4bca8bc3"
Graphs = "86223c79-3864-5bf0-83f7-82e725a168b6"
HiGHS = "87dc4568-4c63-4d18-b0c0-bb2238e4078b"
InteractiveUtils = "b77e0a4c-d291-57a0-90e8-8db25a27a240"
JuMP = "4076af6c-e467-56ae-b986-b466b2749572"
Markdown = "d6f4376e-aef5-505a-96c1-9c027394607a"
MathOptInterface = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[compat]
Bonobo = "~0.1.5"
Graphs = "~1.14.0"
HiGHS = "~1.24.1"
JuMP = "~1.31.1"
MathOptInterface = "~1.52.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.12.7"
manifest_format = "2.0"
project_hash = "6c511736cb6bf2dc26181686ec707fd79116d82e"

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

[[deps.Bonobo]]
deps = ["DataStructures", "NamedTupleTools"]
git-tree-sha1 = "17878aad72be16fecd899699c5a0b26711b46a7d"
uuid = "f7b14807-3d4d-461a-888a-05dd4bca8bc3"
version = "0.1.5"

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

[[deps.CommonSubexpressions]]
deps = ["MacroTools"]
git-tree-sha1 = "cda2cfaebb4be89c9084adaca7dd7333369715c5"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.1"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.3.1+2"

[[deps.DataStructures]]
deps = ["OrderedCollections"]
git-tree-sha1 = "b0bc6d2cad1fed8b7fd59a1551a991cb3d2809e6"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.19.6"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
version = "1.11.0"

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

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions"]
git-tree-sha1 = "1b86cca764a61dcac4fef4c5e16e378e5ed6953c"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "1.4.5"
weakdeps = ["StaticArrays"]

    [deps.ForwardDiff.extensions]
    ForwardDiffStaticArraysExt = "StaticArrays"

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

[[deps.JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7204148362dafe5fe6a273f855b8ccbe4df8173e"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.8.0"

[[deps.JSON]]
deps = ["Dates", "Logging", "Parsers", "PrecompileTools", "StructUtils", "UUIDs", "Unicode"]
git-tree-sha1 = "c7345ab1a7ca4dc8a02c9f6510da0d9857bbe513"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "1.7.1"

    [deps.JSON.extensions]
    JSONArrowExt = ["ArrowTypes"]

    [deps.JSON.weakdeps]
    ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"

[[deps.JuMP]]
deps = ["LinearAlgebra", "MacroTools", "MathOptInterface", "MutableArithmetics", "OrderedCollections", "PrecompileTools", "Printf", "SparseArrays"]
git-tree-sha1 = "614b22ff014355192982b1f9a12c61298ce6a908"
uuid = "4076af6c-e467-56ae-b986-b466b2749572"
version = "1.31.1"

    [deps.JuMP.extensions]
    JuMPDimensionalDataExt = "DimensionalData"

    [deps.JuMP.weakdeps]
    DimensionalData = "0703355e-b756-11e9-17c0-8b28908087d0"

[[deps.JuliaSyntaxHighlighting]]
deps = ["StyledStrings"]
uuid = "ac6e5ff7-fb65-4e79-a425-ec3bc9c03011"
version = "1.12.0"

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
git-tree-sha1 = "f1ccd9ffcb8577e207deb9aaebeb3f961de70380"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "1.52.0"

    [deps.MathOptInterface.extensions]
    MathOptInterfaceBenchmarkToolsExt = "BenchmarkTools"
    MathOptInterfaceCliqueTreesExt = "CliqueTrees"

    [deps.MathOptInterface.weakdeps]
    BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
    CliqueTrees = "60701a23-6482-424a-84db-faee86b9b1f8"

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

[[deps.NamedTupleTools]]
git-tree-sha1 = "90914795fc59df44120fe3fff6742bb0d7adb1d0"
uuid = "d9ec5142-1e00-5aa0-9d6a-321866360f50"
version = "0.14.3"

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

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl"]
git-tree-sha1 = "1346c9208249809840c91b26703912dff463d335"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.6+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "94ba93778373a53bfd5a0caaf7d809c445292ff4"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.8.2"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "3de8f5e6e90ebfa8d6d1f86997d6cdcd6a912ff3"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.7"

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
git-tree-sha1 = "c3ac026e735264e9bdc6a9bcbd1b1e781b36e3bc"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.8.3"

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

[[deps.StructUtils]]
deps = ["Dates", "UUIDs"]
git-tree-sha1 = "2d0fc55c61321ba245c47be599570d11bac50303"
uuid = "ec057cc2-7a8d-4b58-b3b3-92acb9f63b42"
version = "2.8.5"

    [deps.StructUtils.extensions]
    StructUtilsMeasurementsExt = ["Measurements"]
    StructUtilsStaticArraysCoreExt = ["StaticArraysCore"]
    StructUtilsTablesExt = ["Tables"]

    [deps.StructUtils.weakdeps]
    Measurements = "eff96d63-e80a-5855-80a2-b1b0885c5ab7"
    StaticArraysCore = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
    Tables = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"

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
"""

# ╔═╡ Cell order:
# ╟─b88253cb-fed0-4b96-b204-982a29a15f1c
# ╟─bbee4eac-723d-478c-a0a2-911aba5e10b8
# ╠═75a94d33-0c45-4060-acda-4fff648f015f
# ╠═e1c84f8a-bc05-4b45-9a0d-e560fbc8face
# ╠═5241b601-b453-4529-a22a-579c081bc33e
# ╠═4deefab0-4cdd-44bd-9086-b0f7bced4fd6
# ╠═910a5d7a-34a1-4502-9cc4-8e836e2439dd
# ╠═a4becfae-788f-42be-8873-053fdea98e04
# ╠═a9f8fd69-b44d-47f9-95af-2a93a95ae23d
# ╠═dd41517c-a3c5-42aa-b99d-4b0b60af458c
# ╠═26dfc089-7d62-4133-81bd-b420fc4ac7cd
# ╠═c851df34-eada-4d39-a05c-ef27533d6ac4
# ╠═2b001ef4-8049-4c54-b7f4-74895407febc
# ╠═198a23ce-86ea-45c2-833b-dbd89f2ec4dd
# ╠═342bc6e9-8bf5-4237-81cf-0d4d0677d023
# ╟─e659ab67-09eb-4702-ab65-8359e589a6b0
# ╠═1d1870e8-0fac-4b7b-a2a4-3c8e9b9778d2
# ╠═1c7a2307-41c9-4d57-b6f9-9ab7f171c5e5
# ╠═3b4671ab-2453-4686-8328-6f9e9be443e8
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
