"""Visualization helpers (folium + matplotlib) for Streamlit integration."""

import folium
import geopandas as gpd
import matplotlib.pyplot as plt
from branca.element import Template, MacroElement
from . import config

"""Visualization helpers (folium + matplotlib) for Streamlit integration."""

import folium
import geopandas as gpd
from branca.element import Template, MacroElement
from . import config

def create_interactive_map(solution_gdf, demand_gdf, district_poly, coverage_matrix):
    """Generates and returns an interactive Folium map for Streamlit."""
    
    # 1. Calculate centroid in metric CRS to avoid UserWarning, then convert to WGS84
    centroid_metric = gpd.GeoSeries([district_poly], crs=config.CRS_METRIC).centroid.iloc[0]
    centroid_wgs84 = gpd.GeoSeries([centroid_metric], crs=config.CRS_METRIC).to_crs(config.CRS_WGS84).iloc[0]

    # 2. Initialize Map
    m = folium.Map(
        location=[centroid_wgs84.y, centroid_wgs84.x], 
        zoom_start=13, 
        tiles="OpenStreetMap"
    )

    # 3. Add District Boundary
    district_wgs84 = gpd.GeoSeries([district_poly], crs=config.CRS_METRIC).to_crs(config.CRS_WGS84)
    folium.GeoJson(
        district_wgs84.geometry.iloc[0],
        style_function=lambda *_: {"fillOpacity": 0, "color": "black", "weight": 2},
    ).add_to(m)

    # 4. Add Coverage Buffers
    for _, row in solution_gdf.iterrows():
        buff = gpd.GeoSeries([row.geometry.buffer(config.MAX_WALKING_DISTANCE_METERS)],
                             crs=config.CRS_METRIC).to_crs(config.CRS_WGS84).iloc[0]
        folium.GeoJson(
            buff.__geo_interface__,
            style_function=lambda *_: {"fillOpacity": 0.1, "color": "green", "weight": 1},
        ).add_to(m)

    # 5. Add Demand Points (Covered vs Uncovered)
    covered_indices = set(i for i, S in enumerate(coverage_matrix) if len(S) > 0)
    demand_wgs84 = demand_gdf.to_crs(config.CRS_WGS84)

    for i, r in demand_wgs84.iterrows():
        color = "blue" if i in covered_indices else "red"
        folium.CircleMarker(
            [r.geometry.y, r.geometry.x],
            radius=1,
            color=color,
            fill=True,
            fill_opacity=0.5
        ).add_to(m)

    # 6. Add Existing vs New Chargers
    existing_chargers = solution_gdf[solution_gdf.get("existing", False)].to_crs(config.CRS_WGS84)
    new_chargers = solution_gdf[~solution_gdf.get("existing", False)].to_crs(config.CRS_WGS84)

    for _, r in existing_chargers.iterrows():
        folium.Marker(
            [r.geometry.y, r.geometry.x],
            icon=folium.Icon(color="lightgray", icon="bolt", prefix="fa"),
            tooltip="Existing Station"
        ).add_to(m)

    for _, r in new_chargers.iterrows():
        folium.Marker(
            [r.geometry.y, r.geometry.x],
            icon=folium.Icon(color="green", icon="bolt", prefix="fa"),
            tooltip="New Recommended Station"
        ).add_to(m)

    # 7. Add Legend
    legend_html = """
    <div style="position: fixed; bottom: 50px; left: 50px; width: 180px; height: 140px; 
                background-color: white; border:2px solid grey; z-index:9999; 
                font-size:14px; padding: 10px;">
        <b>Legend</b><br>
        <i class="fa fa-circle" style="color:blue"></i> Covered demand<br>
        <i class="fa fa-circle" style="color:red"></i> Uncovered demand<br>
        <i class="fa fa-bolt" style="color:gray"></i> Existing charger<br>
        <i class="fa fa-bolt" style="color:green"></i> New charger
    </div>
    """
    legend = MacroElement()
    legend._template = Template(legend_html)
    m.get_root().add_child(legend)

    # Optional: Save for external use, but return the object for Streamlit
    m.save("set_cover/ev_placement_solution.html")
    return m

def visualize_coverage(demand_gdf, candidates_gdf, coverage_matrix=None):
    """
    Debug visualization: shows which buildings are covered by candidates using metric distances.
    Also draws buffer circles around candidates representing walking distance.
    Adds a legend for colors and symbols.
    """
    # Convert to metric CRS for accurate distance check
    demand_metric = demand_gdf.to_crs(config.CRS_METRIC)
    candidates_metric = candidates_gdf.to_crs(config.CRS_METRIC)
    
    # Compute coverage in metric CRS
    if coverage_matrix is None:
        covered_flags = []
        for i, building in demand_metric.iterrows():
            distances = candidates_metric.geometry.distance(building.geometry)
            covered = (distances <= config.MAX_WALKING_DISTANCE_METERS).any()
            covered_flags.append(covered)
    else:
        covered_flags = [len(cover) > 0 for cover in coverage_matrix]

    demand_metric["covered"] = covered_flags

    # Reproject to WGS84 for Folium
    demand_wgs84 = demand_metric.to_crs(config.CRS_WGS84)
    candidates_wgs84 = candidates_metric.to_crs(config.CRS_WGS84)

    # Map center
    centroid_metric = demand_metric.geometry.unary_union.centroid
    map_center = gpd.GeoSeries([centroid_metric], crs=config.CRS_METRIC).to_crs(config.CRS_WGS84).iloc[0]

    m = folium.Map(location=[map_center.y, map_center.x], zoom_start=13)

    # Buffer circles around candidates
    for _, r in candidates_metric.iterrows():
        buffer_geom = gpd.GeoSeries([r.geometry.buffer(config.MAX_WALKING_DISTANCE_METERS)],
                                    crs=config.CRS_METRIC).to_crs(config.CRS_WGS84).iloc[0]
        folium.GeoJson(
            buffer_geom.__geo_interface__,
            style_function=lambda *_: {"fillOpacity": 0.05, "color": "green", "weight": 1},
        ).add_to(m)

    # Plot demand points
    for _, r in demand_wgs84.iterrows():
        folium.CircleMarker(
            [r.geometry.y, r.geometry.x],
            radius=0.1 if r.covered else 5,
            color="blue" if r.covered else "red",
            fill=True,
            fill_opacity=0.2,
        ).add_to(m)

    # Plot candidates
    for _, r in candidates_wgs84.iterrows():
        folium.CircleMarker(
            [r.geometry.y, r.geometry.x],
            radius=6 if r["existing"] else 3,
            color="pink" if r["existing"] else "orange",
            fill=True,
            fill_opacity=0.5,
        ).add_to(m)

    # --- Legend ---
    template = """
    {% macro html(this, kwargs) %}
    <div style="
        position: fixed; 
        bottom: 50px; left: 50px; width: 180px; height: 140px; 
        background-color: white; z-index:9999; 
        border:2px solid grey; padding: 10px;
        font-size:14px;
    ">
    <b>Legend</b><br>
    <i class="fa fa-circle" style="color:green"></i> Candidate buffer (max walk)<br>
    <i class="fa fa-circle" style="color:orange"></i> New candidate<br>
    <i class="fa fa-circle" style="color:pink"></i> Existing candidate<br>
    <i class="fa fa-circle" style="color:blue"></i> Covered building<br>
    <i class="fa fa-circle" style="color:red"></i> Uncovered building
    </div>
    {% endmacro %}
    """
    macro = MacroElement()
    macro._template = Template(template)
    m.get_root().add_child(macro)

    m.save("set_cover/coverage_debug_map.html")
    print("--- 6. Coverage debug map saved to coverage_debug_map.html")
    return m


def create_static_plot(solution_gdf, demand_gdf):
    """Generates and returns a Matplotlib figure."""
    fig, ax = plt.subplots(figsize=(10, 10))

    existing_chargers = solution_gdf[solution_gdf.get("existing", False)]
    new_chargers = solution_gdf[~solution_gdf.get("existing", False)]

    ax.scatter(demand_gdf.geometry.x, demand_gdf.geometry.y, s=2, 
               label="Buildings", alpha=0.4, color="gray")

    if not existing_chargers.empty:
        ax.scatter(existing_chargers.geometry.x, existing_chargers.geometry.y,
                   s=60, label="Existing Charging Stations", ec="k", color="magenta", zorder=3)
    
    if not new_chargers.empty:
        ax.scatter(new_chargers.geometry.x, new_chargers.geometry.y,
                   s=80, marker="X", label="New Charging Stations", color="green", zorder=4)

    ax.set_aspect("equal")
    ax.axis("off")
    district_clean = config.DISTRICT_NAME.split(',')[0]
    ax.set_title(f"Optimal EV charging stations in\n{district_clean}")
    ax.legend(loc="upper right")
    
    return fig