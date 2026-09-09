from geopandas import GeoDataFrame


class Node:
    """Represents a node in an undirected graph.

    Attributes:
        name (str): Identifier for the node.
        neighbors (set[int]): Indices of adjacent nodes.
        color (int): Assigned color label for graph coloring algorithms. Defaults to -1.
        saturation (int): Saturation degree used in coloring heuristics. Defaults to 0.
    """

    def __init__(self, name: str) -> None:
        """Initializes a Node.

        Args:
            name (str): Name or label for the node.
        """
        self.name = name
        self.neighbors = set()
        self.color = -1
        self.saturation = 0

    def degree(self) -> int:
        """Calculates the degree of the node.

        Returns:
            int: Number of neighbors (degree) of this node.
        """
        return len(self.neighbors)


class Edge:
    """Represents an undirected edge between two nodes.

    Attributes:
        u (int): Index of the first endpoint node.
        v (int): Index of the second endpoint node.
    """

    def __init__(self, u: int, v: int) -> None:
        """Initializes an Edge between two nodes.

        Args:
            u (int): Index of the first node.
            v (int): Index of the second node.
        """
        self.u = u
        self.v = v


class Graph:
    """Represents an undirected graph composed of nodes and edges.

    Attributes:
        nodes (list[Node]): List of Node objects in the graph.
    """

    def __init__(self) -> None:
        """Initializes an empty Graph."""
        self.nodes = []

    def add_node(self, name: str) -> int:
        """Adds a new node to the graph.

        Args:
            name (str): Name or label for the new node.

        Returns:
            int: Index of the newly added node.
        """
        node = Node(name)
        self.nodes.append(node)
        return len(self.nodes) - 1

    def add_edge(self, u_index: int, v_index: int) -> None:
        """Adds an undirected edge between two existing nodes.

        Args:
            u_index (int): Index of the first node.
            v_index (int): Index of the second node.
        """
        self.nodes[u_index].neighbors.add(v_index)
        self.nodes[v_index].neighbors.add(u_index)

    @classmethod
    def from_gdf(cls, gdf: GeoDataFrame, region_column: str) -> "Graph":
        """Builds a Graph from a GeoDataFrame based on spatial relationships.

        Creates a node for each record in the GeoDataFrame, using the specified
        column for naming. Adds an edge between any two nodes whose geometries
        touch or intersect.

        Args:
            gdf (GeoDataFrame): GeoDataFrame containing spatial regions.
            region_column (str): Column name in gdf to use for node names.

        Returns:
            Graph: An instance of Graph with nodes and edges populated.
        """
        graph = cls()

        for _, row in gdf.iterrows():
            graph.add_node(name=row[region_column])

        for i, geom_i in gdf.geometry.items():
            for j, geom_j in gdf.geometry.items():
                if i < j and (geom_i.touches(geom_j) or geom_i.intersects(geom_j)):
                    graph.add_edge(i, j)

        print("Number of graph nodes", len(graph.nodes))
        return graph
