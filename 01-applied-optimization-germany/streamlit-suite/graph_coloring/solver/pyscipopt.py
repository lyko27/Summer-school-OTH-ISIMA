import contextlib
import io
import os
import tempfile

from pyscipopt import SCIP_PARAMSETTING, Model, quicksum

from ..graph import Graph


class PySCIPOptSolver:
    """Graph coloring solver using an integer linear programming formulation with PySCIPOpt.

    Constructs a binary variable x[v, k] indicating if vertex v is assigned color k,
    and y[k] indicating if color k is used, then minimizes the number of colors.

    Attributes:
        g (Graph): The graph instance to be colored.
        result (int): The number of colors used in the ILP solution.
        time_limit (float): Time limit for the solver in seconds.
        gap (float): Relative gap limit for the solver.
        presolve (bool): Whether to use presolving.
    """

    def __init__(
        self,
        graph: Graph,
        time_limit=60.0,
        gap=0.0,
        presolve_mode="default",
        *args,
        **kwargs,
    ):
        """Initialize the PySCIPOpt solver.

        Args:
            graph (Graph): The graph to color.
            time_limit (float): Time limit in seconds (0 for no limit).
            gap (float): Relative gap limit (0 for optimal solution).
            presolve_mode (str): Presolving mode ('off', 'fast', 'default', 'aggressive').
            *args: Additional positional arguments for the BaseSolver.
            **kwargs: Additional keyword arguments for the BaseSolver.
        """
        self.g = graph
        self.time_limit = time_limit
        self.gap = gap
        self.presolve_mode = presolve_mode
        self.model = None
        self.constraints = {}
        self.log_output = ""  # will hold captured solver output
        super().__init__(*args, **kwargs)

    @classmethod
    def get_parameter_info(cls):
        """Return information about configurable parameters for the UI.

        Returns:
            dict: Parameter information with types and default values
        """
        return {
            "time_limit": {
                "type": "float",
                "default": 60.0,
                "min": 0.0,
                "max": 3600.0,
                "step": 1.0,
                "help": "Time limit in seconds (0 for no limit)",
            },
            "gap": {
                "type": "float",
                "default": 0.0,
                "min": 0.0,
                "max": 1.0,
                "step": 0.01,
                "help": "Relative gap limit (0 for optimal solution)",
            },
            "presolve_mode": {
                "type": "select",
                "default": "default",
                "options": ["off", "fast", "default", "aggressive"],
                "help": "Presolving mode",
            },
        }

    def solve(self, *args, **kwargs) -> None:
        """Formulate and solve the ILP for graph coloring using PySCIPOpt.

        Defines binary variables x[v_idx, k] and y[k], adds constraints to ensure
        each vertex has exactly one color, adjacent vertices differ, and link x to y,
        then solves to minimize total y[k]. Updates node colors and result.

        Returns:
            None
        """
        self.model = Model("GraphColoring")
        model = self.model
        # ensure SCIP prints detailed log to logfile
        try:
            model.setIntParam("display/verblevel", 4)
        except Exception:
            pass
        try:
            model.setIntParam("display/freq", 1)
        except Exception:
            pass
        try:
            model.setBoolParam("display/lpinfo", True)
        except Exception:
            pass

        # Apply solver parameters
        if self.time_limit > 0:
            model.setRealParam("limits/time", self.time_limit)
        if self.gap > 0:
            model.setRealParam("limits/gap", self.gap)

        # Set presolving mode
        if self.presolve_mode == "off":
            model.setPresolve(SCIP_PARAMSETTING.OFF)
        elif self.presolve_mode == "fast":
            model.setPresolve(SCIP_PARAMSETTING.FAST)
        elif self.presolve_mode == "aggressive":
            model.setPresolve(SCIP_PARAMSETTING.AGGRESSIVE)
        else:  # default
            model.setPresolve(SCIP_PARAMSETTING.DEFAULT)

        num_nodes = len(self.g.nodes)
       # Let k be the number of colors 
        K = num_nodes

        x = {}
        y = {}

        # Add variables
        for v_idx, node in enumerate(self.g.nodes):
            for k in range(K):
                x[v_idx, k] = model.addVar(vtype="B", name=f"x_{v_idx}_{k}")

        for k in range(K):
            y[k] = model.addVar(vtype="B", name=f"y_{k}")

        # Add constraints
        self.constraints = {}

        # Each vertex must have exactly one color
        for v_idx in range(num_nodes):
            cons = model.addCons(
                quicksum(x[v_idx, k] for k in range(K)) == 1,
                name=f"vertex_{v_idx}_one_color",
            )
            self.constraints[f"vertex_{v_idx}_one_color"] = cons

        # Adjacent vertices must have different colors
        #################### TODO ########################
        ###### Implement a constraint that guarantees
        ###### adjacent vertices to have different colors
        ##################################################
        # TODO 1 :
        for v_idx in range(num_nodes):
            for u_idx in self.g.nodes[v_idx].neighbors:
                for k in range(K):
                    cons = model.addCons(x[v_idx, k] + x[u_idx, k] <= 1, name=f"adjacent_{v_idx}_{u_idx}_{k}")
                    self.constraints[f"adjacent_{v_idx}_{u_idx}_{k}"] = cons

        # Link x and y variables
        #################### TODO ########################
        ###### Implement a constraint that links the
        ###### x and y variables
        ##################################################
       # TODO 2 : 
        for v_idx in range(num_nodes):
            for k in range(K):
                cons = model.addCons(x[v_idx, k] <= y[k], name=f"link_{v_idx}_{k}")
                self.constraints[f"link_{v_idx}_{k}"] = cons

        # Minimize total number of colors

        model.setObjective(quicksum(y[k] for k in range(K)), "minimize")

        # Capture solver stdout/stderr during optimize
        tmp_log = tempfile.NamedTemporaryFile(delete=False, suffix=".log")
        tmp_log_path = tmp_log.name
        tmp_log.close()
        # direct SCIP log to temporary file
        try:
            model.setLogfile(tmp_log_path)
        except Exception:
            pass

        # run optimizer
        try:
            model.optimize()
        finally:
            pass

        # read logfile
        try:
            with open(tmp_log_path, "r", encoding="utf-8", errors="replace") as _f:
                self.log_output = _f.read()
        except Exception:
            self.log_output = ""

        try:
            os.unlink(tmp_log_path)
        except Exception:
            pass

        # If logfile empty, try capturing printStatistics() output as fallback
        if not self.log_output.strip():
            try:
                buf_stats = io.StringIO()
                with contextlib.redirect_stdout(buf_stats):
                    try:
                        model.printStatistics()
                    except Exception:
                        pass
                stats_text = buf_stats.getvalue()
                if stats_text:
                    self.log_output = stats_text
            except Exception:
                pass

        # Read solution values
        for v_idx, node in enumerate(self.g.nodes):
            for k in range(K):
                try:
                    val = model.getVal(x[v_idx, k])
                except Exception:
                    val = 0
                if val is not None and val > 0.5:
                    node.color = k
                    break

        distinct = {node.color for node in self.g.nodes}
        self.result = len(distinct)

    def get_solver_log(self):
        """Return captured solver log output."""
        return self.log_output

    def get_constraint_info(self):
        """Get information about the current constraints in the model.

        Returns:
            dict: Dictionary with constraint names and their details
        """
        if not self.model:
            return {}

        result = {}
        for name, cons in self.constraints.items():
            result[name] = {
                "name": name,
                "type": name.split("_")[0] if "_" in name else "custom",
            }
        return result

    def remove_constraint(self, constraint_name):
        """Remove a constraint from the model by name.

        Args:
            constraint_name (str): Name of the constraint to remove

        Returns:
            bool: True if constraint was removed, False otherwise
        """
        if not self.model or constraint_name not in self.constraints:
            return False

        try:
            cons = self.constraints[constraint_name]
            self.model.delCons(cons)
            del self.constraints[constraint_name]
            return True
        except Exception as e:
            print(f"Error removing constraint: {e}")
            return False

    def add_custom_constraint(self, constraint_expr, name=None):
        """Add a custom constraint to the model.

        Args:
            constraint_expr: The constraint expression
            name (str, optional): Name for the constraint

        Returns:
            str: Name of the added constraint
        """
        if not self.model:
            self.model = Model("GraphColoring")

        if name is None:
            name = f"custom_constraint_{len(self.constraints)}"

        cons = self.model.addCons(constraint_expr, name=name)
        self.constraints[name] = cons
        return name
