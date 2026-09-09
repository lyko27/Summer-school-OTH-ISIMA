import heapq
from ..graph import Graph


class DsaturSolver:
    """Graph coloring solver using the DSATUR (Degree of Saturation) heuristic.

    This solver iteratively selects the uncolored vertex with highest saturation
    (number of distinct neighbor colors), breaking ties by degree, and assigns
    the smallest feasible color.

    Attributes:
        g (Graph): The graph instance to be colored.
        result (int): The number of colors used in the final coloring.
    """

    def __init__(self, graph: Graph, *args, **kwargs):
        """Initialize the DSATUR solver.

        Args:
            graph (Graph): The graph to color.
            *args: Additional positional arguments for the BaseSolver.
            **kwargs: Additional keyword arguments for the BaseSolver.
        """
        self.g = graph
        super().__init__(*args, **kwargs)
        
    @classmethod
    def get_parameter_info(cls):
        """Return information about configurable parameters for the UI.
        
        Returns:
            dict: Parameter information with types and default values
        """
        return {}  # DSATUR has no configurable parameters

    def solve(self, *args, **kwargs) -> None:
        """Execute the DSATUR heuristic and set solver result.

        Colors vertices based on saturation degree, updating each node's color
        and computing the total number of colors used.

        Returns:
            None
        """
        n = len(self.g.nodes)
        neighbor_colors = [set() for _ in range(n)]

        heap = [(-0, -self.g.nodes[i].degree(), i) for i in range(n)]
        heapq.heapify(heap)

        while heap:
            _, _, u = heapq.heappop(heap)
            if self.g.nodes[u].color != -1:
                continue

            used_colors = {
                self.g.nodes[v].color
                for v in self.g.nodes[u].neighbors
                if self.g.nodes[v].color != -1
            }
            for color in range(n):
                if color not in used_colors:
                    self.g.nodes[u].color = color
                    break

            for v in self.g.nodes[u].neighbors:
                if self.g.nodes[v].color == -1:
                    if self.g.nodes[u].color not in neighbor_colors[v]:
                        neighbor_colors[v].add(self.g.nodes[u].color)
                        self.g.nodes[v].saturation += 1
                    heapq.heappush(
                        heap,
                        (-self.g.nodes[v].saturation, -self.g.nodes[v].degree(), v),
                    )
        self.result = max(node.color for node in self.g.nodes) + 1
