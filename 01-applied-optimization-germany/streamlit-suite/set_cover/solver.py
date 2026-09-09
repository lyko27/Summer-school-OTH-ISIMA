"""
Optimization module using PySCIPOpt.
"""

from pyscipopt import Model, quicksum
import pandas as pd
import geopandas as gpd
from . import config, data_loader

class EvPlacementSolver:
    """
    Solver for the EV Charger Set Cover problem.
    """

    def __init__(self):
        self.demand_points = None
        self.candidates = None
        self.district_poly = None
        self.coverage_matrix = None
        self.result = None

    def load_data(self):
        """Loads spatial data and prepares the coverage matrix."""
        self.district_poly = data_loader.fetch_district_polygon(config.DISTRICT_NAME, config.CRS_METRIC)
        self.demand_points = data_loader.fetch_demand_points(self.district_poly, config.CRS_METRIC, config.CRS_WGS84)
        
        existing = data_loader.fetch_existing_chargers(self.district_poly, config.CRS_METRIC)
        grid = data_loader.create_candidate_locations(self.district_poly, config.GRID_SPACING_METERS, config.CRS_METRIC)
        
        self.candidates = pd.concat([existing, grid], ignore_index=True).reset_index(drop=True)
        self.coverage_matrix = data_loader.prepare_coverage_matrix(
            self.demand_points, self.candidates, config.MAX_WALKING_DISTANCE_METERS
        )

    def run(self):
        """
        Formulates and solves the Integer Linear Program.
        """
        model = Model("EV_SetCover")
        vars = {}

        # 1. Variables: Minimize NEW stations, require EXISTING ones
        for i, row in self.candidates.iterrows():
            is_existing = bool(row.get("existing", False))
            # Objective weight 0 for existing, 1 for new
            vars[i] = model.addVar(vtype="B", name=f"x_{i}", obj=0.0 if is_existing else 1.0)
            if is_existing:
                model.addCons(vars[i] == 1)

        # 2. Coverage Constraints
        #################### TODO ####################
        ###### Add constraint implements the coverage
        ##############################################

        for cov_set in self.coverage_matrix:
            if cov_set:  # On s'assure qu'au moins une station peut couvrir ce bâtiment
                model.addCons(quicksum(vars[i] for i in cov_set) >= 1)

        model.optimize()

        if model.getStatus() == "optimal":
            chosen_indices = [i for i in vars if model.getVal(vars[i]) > 0.5]
            self.result = self.candidates.iloc[chosen_indices].copy()
        else:
            print(f"Solver status: {model.getStatus()}")

    def get_result(self):
        """Returns the GeoDataFrame of selected locations."""
        return self.result