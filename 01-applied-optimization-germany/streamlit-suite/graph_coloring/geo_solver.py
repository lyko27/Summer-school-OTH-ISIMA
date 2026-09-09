from geopandas import GeoDataFrame
import matplotlib.pyplot as plt
import numpy as np
import networkx as nx
from shapely.geometry import Point

from .graph import Graph 
from typing import Type, Dict, Any, Optional


class GeoColoringUtility:
    """
    Utility to build a region adjacency graph from a GeoDataFrame and process coloring results.
    """

    def __init__(self, gdf: GeoDataFrame, region_column: str):
        """
        Initialize the utility with geospatial data.

        Args:
            gdf (GeoDataFrame): Geospatial data containing region geometries.
            region_column (str): Column name in `gdf` representing region identifiers.
        """
        self.gdf = gdf
        self.region_column = region_column
        self.g: Graph | None = None
        self.mapped_node_colors = None
        self.node_positions: Dict[str, tuple] = {}  # Store node positions for visualization

    def build_graph(self) -> Graph:
        """
        Construct a graph representing adjacency of regions in the GeoDataFrame.

        The graph nodes correspond to regions, and edges connect adjacent regions.
        Also computes and stores node positions based on region centroids.

        Returns:
            Graph: A graph constructed from the GeoDataFrame.
        """
        self.g = Graph.from_gdf(gdf=self.gdf, region_column=self.region_column)
        
        # Calculate and store node positions based on region centroids
        region_to_idx = {node.name: i for i, node in enumerate(self.g.nodes)}
        
        for idx, row in self.gdf.iterrows():
            region_name = row[self.region_column]
            if region_name in region_to_idx:
                # Get centroid of the region's geometry
                centroid = row.geometry.centroid
                self.node_positions[region_name] = (centroid.x, centroid.y)
        
        return self.g

    def postprocess(self, result: int):
        """
        Process solver results by mapping raw color labels to actual color values.

        Args:
            result (int): The number of colors used or the solver result code (unused for mapping).

        Side Effects:
            Updates `self.mapped_node_colors` with a mapping from region names to RGBA color tuples.
        """
        # 1) collect raw labels
        node_color_dict = {node.name: node.color for node in self.g.nodes}

        distinct_labels = sorted(set(node_color_dict.values()))

        label_to_idx = {label: idx for idx, label in enumerate(distinct_labels)}

        n_colors = len(distinct_labels)
        idx_to_color = self._generate_color_map(n_colors)

        self.mapped_node_colors = {
            name: idx_to_color[label_to_idx[label]]
            for name, label in node_color_dict.items()
        }

    @staticmethod
    def _generate_color_map(n_colors):
        """
        Generate a color mapping for a given number of labels using a matplotlib colormap.

        Args:
            n_colors (int): Number of distinct colors required.

        Returns:
            dict[int, tuple]: A dictionary mapping label indices to RGBA color tuples.
        """
        cmap = plt.get_cmap("tab20")
        return {i: cmap(i % 20) for i in range(n_colors)}
        
    def plot_graph(self, ax: Optional[plt.Axes] = None) -> plt.Axes:
        """
        Plot the graph representation with nodes positioned according to region centroids.
        
        Args:
            ax (Optional[plt.Axes]): Matplotlib axes to plot on. If None, creates a new figure.
            
        Returns:
            plt.Axes: The axes with the plotted graph.
        """
        if ax is None:
            _, ax = plt.subplots(figsize=(8, 6))
            
        if not self.g or not self.mapped_node_colors:
            ax.text(0.5, 0.5, "No graph data available", 
                   horizontalalignment='center', verticalalignment='center')
            return ax
            
        # Create a NetworkX graph for visualization
        G = nx.Graph()
        
        # Normalize positions to fit in the plot
        if self.node_positions:
            # Extract positions as a list of coordinates
            positions = np.array(list(self.node_positions.values()))
            
            # Calculate min and max for normalization
            min_x, min_y = positions.min(axis=0)
            max_x, max_y = positions.max(axis=0)
            
            # Normalize to [0.1, 0.9] range to keep some margin
            normalized_positions = {}
            for name, (x, y) in self.node_positions.items():
                norm_x = 0.1 + 0.8 * (x - min_x) / (max_x - min_x) if max_x > min_x else 0.5
                norm_y = 0.1 + 0.8 * (y - min_y) / (max_y - min_y) if max_y > min_y else 0.5
                normalized_positions[name] = (norm_x, norm_y)
        else:
            # If no positions available, use spring layout
            normalized_positions = None
        
        # Add nodes and edges to the NetworkX graph
        for i, node in enumerate(self.g.nodes):
            G.add_node(i, name=node.name)
            
        for i, node in enumerate(self.g.nodes):
            for neighbor_idx in node.neighbors:
                if i < neighbor_idx:  # Add each edge only once
                    G.add_edge(i, neighbor_idx)
        
        # Create a position dictionary for NetworkX
        if normalized_positions:
            pos = {i: normalized_positions[node.name] 
                  for i, node in enumerate(self.g.nodes) 
                  if node.name in normalized_positions}
        else:
            pos = nx.spring_layout(G)
            
        # Draw the graph
        node_colors = [self.mapped_node_colors.get(self.g.nodes[i].name, (0.7, 0.7, 0.7, 1.0)) 
                      for i in range(len(self.g.nodes))]
        
        nx.draw_networkx_nodes(G, pos, ax=ax, node_color=node_colors, 
                              node_size=300, alpha=0.8)
        nx.draw_networkx_edges(G, pos, ax=ax, width=1.0, alpha=0.5)
        
        # Add node labels
        labels = {i: self.g.nodes[i].name for i in range(len(self.g.nodes))}
        nx.draw_networkx_labels(G, pos, labels, ax=ax, font_size=8, 
                               font_color='black', font_weight='bold')
        
        return ax


class GeoSolverWrapper:
    """
    Wrapper to integrate a graph coloring solver with geospatial data utilities.

    This class builds the adjacency graph from a GeoDataFrame, runs the solver,
    and postprocesses the results to color the regions.
    """

    def __init__(
        self, SolverClass: Type, gdf: GeoDataFrame, region_column: str, *args, **kwargs
    ):
        """
        Initialize the solver wrapper with a solver class and geospatial data.

        Args:
            SolverClass (Type): A class implementing a graph coloring solver interface.
            gdf (GeoDataFrame): Geospatial data containing region geometries.
            region_column (str): Column name in `gdf` representing region identifiers.
            *args: Additional positional arguments forwarded to the solver.
            **kwargs: Additional keyword arguments forwarded to the solver.
        """
        self.geo_util = GeoColoringUtility(gdf, region_column)
        graph = self.geo_util.build_graph()
        self.solver = SolverClass(graph=graph, *args, **kwargs)

    def run(self, *args, **kwargs):
        """
        Execute the graph coloring solver.

        Args:
            *args: Additional positional arguments for the solver's run method.
            **kwargs: Additional keyword arguments for the solver's run method.
        """
        self.solver.solve(*args, **kwargs)

    def postprocess(self):
        """
        Apply postprocessing of the solver results to generate region color mappings.
        """
        self.geo_util.postprocess(self.result)

    @property
    def result(self) -> int:
        """
        Retrieve the result of the solver run.

        Returns:
            int: The result code or number of colors used by the solver.
        """
        return self.solver.result

    @property
    def g(self) -> Graph:
        """
        Access the underlying graph used by the solver.

        Returns:
            Graph: The adjacency graph of regions.
        """
        return self.solver.g
