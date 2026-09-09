"""
Data loading and spatial processing module.
Optimized for performance and documented in Sphinx style.
"""

import math
import logging
import geopandas as gpd
import numpy as np
import osmnx as ox
from shapely.geometry import Point
from typing import List, Set

# Relative import to ensure it works within the 'set_cover' package
from . import config

# Mute redundant OSMnx logs
ox.settings.log_console = False
logger = logging.getLogger(__name__)

def fetch_district_polygon(district_name: str, crs_metric: int):
    """
    Fetches the boundary polygon for a district and projects it.

    :param district_name: Name of the area (e.g., "Clermont-Ferrand, France").
    :param crs_metric: The metric EPSG code for projection.
    :return: A Shapely polygon of the district boundary.
    """
    print(f"--- 1. Fetching boundary for '{district_name}'...")
    
    try:
        gdf = ox.geocode_to_gdf(district_name)
    except Exception as e:
        print(f"\n[!] ERREUR : Impossible de trouver '{district_name}' dans la base de données OpenStreetMap.")
        print("Veuillez vérifier l'orthographe ou essayer d'ajouter le pays (par exemple, 'Clermont-Ferrand, France').\n")
        raise ValueError(f"Le lieu '{district_name}' est introuvable.") from e

    if gdf.crs is None:
        gdf.set_crs(config.CRS_WGS84, inplace=True)
    return gdf.to_crs(crs_metric).geometry.iloc[0]

def fetch_demand_points(district_poly, crs_metric: int, crs_wgs84: int) -> gpd.GeoDataFrame:
    """
    Creates demand points from building centroids via OSM.

    :param district_poly: The district boundary geometry.
    :param crs_metric: Metric CRS for centroid calculation.
    :param crs_wgs84: WGS84 CRS for OSM fetching.
    :return: GeoDataFrame of demand point centroids.
    """
    print("--- 2. Fetching buildings to create demand points...")
    poly_wgs84 = gpd.GeoSeries([district_poly], crs=crs_metric).to_crs(crs_wgs84).iloc[0]
    
    try:
        buildings = ox.features_from_polygon(poly_wgs84, tags={"building": True})
        # Filter for polygons and project
        buildings = buildings[buildings.geom_type == "Polygon"].to_crs(crs_metric)
    except Exception:
        print("    --> No buildings found in OSM; using synthetic grid fallback.")
        buildings = gpd.GeoDataFrame(geometry=[], crs=crs_metric)

    if buildings.empty:
        # Fallback: Create a synthetic grid if OSM data is missing
        minx, miny, maxx, maxy = district_poly.bounds
        xs, ys = np.meshgrid(np.linspace(minx, maxx, 50), np.linspace(miny, maxy, 50))
        pts = [Point(x, y) for x, y in zip(xs.flatten(), ys.flatten()) if Point(x, y).within(district_poly)]
        buildings = gpd.GeoDataFrame(geometry=pts, crs=crs_metric)

    demand = gpd.GeoDataFrame(geometry=buildings.geometry.centroid, crs=crs_metric)
    print(f"    --> Found {len(demand):,} demand points.")
    return demand.reset_index(drop=True)

def fetch_existing_chargers(district_poly, crs_metric: int) -> gpd.GeoDataFrame:
    """
    Fetches existing charging stations from OSM.

    :param district_poly: Boundary geometry.
    :param crs_metric: Metric CRS.
    :return: GeoDataFrame of existing charger points.
    """
    print("--- 3. Fetching existing EV chargers...")
    poly_wgs84 = gpd.GeoSeries([district_poly], crs=crs_metric).to_crs(config.CRS_WGS84).iloc[0]
    
    try:
        gdf = ox.features_from_polygon(poly_wgs84, tags={"amenity": "charging_station"})
        chargers = gdf[gdf.geom_type == "Point"].to_crs(crs_metric)[["geometry"]].copy()
    except Exception:
        chargers = gpd.GeoDataFrame(columns=["geometry"], crs=crs_metric)
    
    chargers["existing"] = True
    print(f"    --> Found {len(chargers):,} existing chargers.")
    return chargers

def create_candidate_locations(district_poly, spacing: float, crs_metric: int) -> gpd.GeoDataFrame:
    """
    Generates a hexagonal grid of candidate locations.

    :param district_poly: Boundary to fill.
    :param spacing: Hexagonal spacing parameter.
    :param crs_metric: Metric CRS.
    :return: GeoDataFrame of candidate points.
    """
    print("--- 4. Generating candidate location grid...")
    minx, miny, maxx, maxy = district_poly.bounds
    dx = spacing * 1.5
    dy = spacing * math.sqrt(3)

    cols = np.arange(minx - spacing, maxx + spacing, dx)
    rows = np.arange(miny - spacing, maxy + spacing, dy)

    points = [
        Point(x + (spacing * 0.75 if j % 2 else 0), y)
        for j, y in enumerate(rows)
        for x in cols
    ]
    
    candidates = gpd.GeoDataFrame(geometry=points, crs=crs_metric)
    # Perform vectorized spatial filter
    candidates = candidates[candidates.geometry.within(district_poly)].copy()
    candidates["existing"] = False
    print(f"    --> Generated {len(candidates):,} candidate points.")
    return candidates.reset_index(drop=True)

def prepare_coverage_matrix(demand_gdf: gpd.GeoDataFrame, 
                            candidates_gdf: gpd.GeoDataFrame, 
                            d_max: float) -> List[Set[int]]:
    """
    Calculates coverage using vectorized NumPy operations for high performance.

    :param demand_gdf: GeoDataFrame of buildings.
    :param candidates_gdf: GeoDataFrame of candidate sites.
    :param d_max: Maximum allowed walking distance.
    :return: List of sets containing candidate indices for each demand point.
    """
    print(f"--- 5. Calculating coverage matrix for {len(demand_gdf)} buildings...")
    
    # PERFORMANCE: Convert geometries to NumPy coordinate arrays
    cand_coords = np.array([[p.x, p.y] for p in candidates_gdf.geometry])
    coverage = []

    for building in demand_gdf.geometry:
        b_coord = np.array([building.x, building.y])
        # Vectorized Euclidean distance calculation
        distances = np.linalg.norm(cand_coords - b_coord, axis=1)
        covering_idxs = np.where(distances <= d_max)[0]
        coverage.append(set(covering_idxs.tolist()))

    if any(len(s) == 0 for s in coverage):
        logger.warning(f"Optimization warning: Some buildings are not covered within {d_max}m.")

    print("    --> Coverage matrix prepared.")
    return coverage