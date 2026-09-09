from typing import Any, Dict

import folium
import geopandas as gpd
import networkx as nx
import numpy as np
import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from shapely.validation import make_valid
from streamlit_folium import st_folium
from streamlit_plotly_events import plotly_events

from graph_coloring.geo_solver import GeoSolverWrapper
from graph_coloring.solver.dsatur import DsaturSolver
from graph_coloring.solver.pyscipopt import PySCIPOptSolver

# GeoJSON URLs per country
COUNTRY_GEOJSON = {
    "Germany": "https://gist.githubusercontent.com/fegoa89/d33514a5e59eb5af812b909915bcb3da/raw/germany-states.geojson",
    "Italy": "https://raw.githubusercontent.com/openpolis/geojson-italy/master/geojson/limits_IT_provinces.geojson",
    "Spain": "https://raw.githubusercontent.com/codeforgermany/click_that_hood/main/public/data/spain-communities.geojson",
    "France": "https://raw.githubusercontent.com/gregoiredavid/france-geojson/master/regions-version-simplifiee.geojson",
    "Poland": "https://raw.githubusercontent.com/codeforgermany/click_that_hood/main/public/data/poland.geojson",
    "Europe": "https://raw.githubusercontent.com/leakyMirror/map-of-europe/master/GeoJSON/europe.geojson",
    "World": "https://raw.githubusercontent.com/johan/world.geo.json/master/countries.geo.json",
}

# Region name column per country
REGION_NAME_COLUMN = {
    "France": "nom",
    "Germany": "NAME_1",
    "Italy": "prov_name",
    "Spain": "name",
    "Poland": "name",
    "Europe": "NAME",
    "World": "name",
}

# Available solvers
SOLVER_OPTIONS = {
    "DSATUR": DsaturSolver,
    "IP": PySCIPOptSolver
}

st.set_page_config(layout="wide")
st.title("Graph Coloring Visualization")


# Function to create parameter input widgets based on parameter info
def create_parameter_inputs(solver_class) -> Dict[str, Any]:
    """Create input widgets for solver parameters and return their values."""
    param_info = solver_class.get_parameter_info()
    param_values = {}

    for param_name, param_config in param_info.items():
        param_type = param_config["type"]
        default = param_config["default"]
        help_text = param_config.get("help", "")

        if param_type == "int":
            min_val = param_config.get("min", 0)
            max_val = param_config.get("max", 100)
            if param_config.get("optional", False) and default is None:
                use_param = st.checkbox(f"Use {param_name}", False, help=help_text)
                if use_param:
                    param_values[param_name] = st.number_input(
                        f"{param_name}", min_val, max_val, min_val, 1, help=help_text
                    )
                else:
                    param_values[param_name] = None
            else:
                param_values[param_name] = st.number_input(
                    f"{param_name}", min_val, max_val, default, 1, help=help_text
                )

        elif param_type == "float":
            min_val = param_config.get("min", 0.0)
            max_val = param_config.get("max", 100.0)
            step = param_config.get("step", 0.1)
            param_values[param_name] = st.slider(
                f"{param_name}", min_val, max_val, default, step, help=help_text
            )

        elif param_type == "bool":
            param_values[param_name] = st.checkbox(
                f"{param_name}", default, help=help_text
            )

        elif param_type == "select":
            options = param_config.get("options", [])
            param_values[param_name] = st.selectbox(
                f"{param_name}",
                options,
                index=options.index(default) if default in options else 0,
                help=help_text,
            )

    return param_values


# Sidebar controls
with st.sidebar:
    st.header("Configuration")
    selected_country = st.selectbox("Select Country", list(COUNTRY_GEOJSON.keys()))
    selected_solver = st.selectbox("Select Optimizer", list(SOLVER_OPTIONS.keys()))

    # Create a container for solver-specific parameters
    st.subheader(f"{selected_solver} Parameters")
    solver_class = SOLVER_OPTIONS[selected_solver]
    solver_params = create_parameter_inputs(solver_class)

    run_button = st.button("Run Coloring")

# Main logic
if run_button:
    # Load GeoJSON
    st.info("📥 Loading map data...")
    gdf = gpd.read_file(COUNTRY_GEOJSON[selected_country])
    region_column = REGION_NAME_COLUMN[selected_country]

    # Run solver
    st.info("🎨 Coloring regions...")
    SolverClass = SOLVER_OPTIONS[selected_solver]
    geo_solver = GeoSolverWrapper(
        SolverClass, gdf=gdf, region_column=region_column, **solver_params
    )
    geo_solver.run()
    geo_solver.postprocess()

    # Plot results
    st.subheader(f"{selected_country} Colored Regions")

    # Create a two-column layout for map and graph
    col1, col2 = st.columns(2)

    with col1:
        # Interactive map visualization using Folium
        st.write("### Interactive Map")

        # Create a Folium map centered on the data
        gdf["geometry"] = gdf["geometry"].apply(make_valid)
        # Optional: filter out empty geometries after fixing
        gdf = gdf[~gdf.is_empty]
        # Now run your union safely
        centroid = gdf.geometry.union_all().centroid

        m = folium.Map(location=[centroid.y, centroid.x], zoom_start=4)

        # Add colored regions to the map
        gdf["color_hex"] = (
            gdf[region_column]
            .map(
                {
                    name: f"#{int(color[0] * 255):02x}{int(color[1] * 255):02x}{int(color[2] * 255):02x}"
                    for name, color in geo_solver.geo_util.mapped_node_colors.items()
                }
            )
            .fillna("#CCCCCC")
        )

        for col in gdf.columns:
            if pd.api.types.is_datetime64_any_dtype(gdf[col]):
                gdf[col] = gdf[col].astype(str)

        # Add GeoJSON to the map
        folium.GeoJson(
            gdf,
            style_function=lambda feature: {
                "fillColor": feature["properties"]["color_hex"],
                "color": "black",
                "weight": 1,
                "fillOpacity": 0.7,
            },
            tooltip=folium.GeoJsonTooltip(fields=[region_column], aliases=["Region"]),
        ).add_to(m)

        # Display the map
        st_folium(m, key="main_map", use_container_width=True, height=500, returned_objects=[])

    with col2:
        # Interactive graph visualization using Plotly
        st.write("### Interactive Graph")

        # Create a NetworkX graph
        G = nx.Graph()

        # Add nodes and edges
        for i, node in enumerate(geo_solver.g.nodes):
            G.add_node(i, name=node.name)

        for i, node in enumerate(geo_solver.g.nodes):
            for neighbor_idx in node.neighbors:
                if i < neighbor_idx:  # Add each edge only once
                    G.add_edge(i, neighbor_idx)

        # Get node positions
        if geo_solver.geo_util.node_positions:
            # Normalize positions
            positions = np.array(list(geo_solver.geo_util.node_positions.values()))
            min_x, min_y = positions.min(axis=0)
            max_x, max_y = positions.max(axis=0)

            pos = {}
            for name, (x, y) in geo_solver.geo_util.node_positions.items():
                norm_x = (x - min_x) / (max_x - min_x) if max_x > min_x else 0.5
                norm_y = (y - min_y) / (max_y - min_y) if max_y > min_y else 0.5
                node_idx = next(
                    i for i, node in enumerate(geo_solver.g.nodes) if node.name == name
                )
                pos[node_idx] = (norm_x, norm_y)
        else:
            pos = nx.spring_layout(G)

        # Create node trace
        node_x = []
        node_y = []
        node_colors = []
        node_text = []

        for node_idx in G.nodes():
            x, y = pos[node_idx]
            node_x.append(x)
            node_y.append(y)
            node_name = geo_solver.g.nodes[node_idx].name
            node_color = geo_solver.geo_util.mapped_node_colors.get(
                node_name, (0.7, 0.7, 0.7, 1.0)
            )
            node_colors.append(
                f"rgba({int(node_color[0] * 255)},{int(node_color[1] * 255)},{int(node_color[2] * 255)},{node_color[3]})"
            )
            node_text.append(
                f"Region: {node_name}<br>Color: {geo_solver.g.nodes[node_idx].color}"
            )

        node_trace = go.Scatter(
            x=node_x,
            y=node_y,
            mode="markers+text",
            text=[geo_solver.g.nodes[i].name for i in G.nodes()],
            textposition="top center",
            textfont=dict(size=8),
            hoverinfo="text",
            hovertext=node_text,
            marker=dict(
                showscale=False,
                color=node_colors,
                size=15,
                line=dict(width=1, color="black"),
            ),
        )

        # Create edge trace
        edge_x = []
        edge_y = []

        for edge in G.edges():
            x0, y0 = pos[edge[0]]
            x1, y1 = pos[edge[1]]
            edge_x.extend([x0, x1, None])
            edge_y.extend([y0, y1, None])

        edge_trace = go.Scatter(
            x=edge_x,
            y=edge_y,
            line=dict(width=1, color="#888"),
            hoverinfo="none",
            mode="lines",
        )

        # Create the figure
        fig = go.Figure(
            data=[edge_trace, node_trace],
            layout=go.Layout(
                showlegend=False,
                hovermode="closest",
                margin=dict(b=0, l=0, r=0, t=0),
                xaxis=dict(showgrid=False, zeroline=False, showticklabels=False),
                yaxis=dict(showgrid=False, zeroline=False, showticklabels=False),
                dragmode="pan",
            ),
        )

        # Add buttons for zoom and pan
        fig.update_layout(
            updatemenus=[
                dict(
                    type="buttons",
                    direction="left",
                    buttons=[
                        dict(
                            args=[{"dragmode": "pan"}], label="Pan", method="relayout"
                        ),
                        dict(
                            args=[{"dragmode": "zoom"}], label="Zoom", method="relayout"
                        ),
                        dict(
                            args=[
                                {
                                    "xaxis.range": [
                                        min(
                                            [
                                                x
                                                for trace in fig.data
                                                for x in trace.x
                                                if x is not None
                                            ]
                                        )
                                        - 0.05,
                                        max(
                                            [
                                                x
                                                for trace in fig.data
                                                for x in trace.x
                                                if x is not None
                                            ]
                                        )
                                        + 0.05,
                                    ],
                                    "yaxis.range": [
                                        min(
                                            [
                                                y
                                                for trace in fig.data
                                                for y in trace.y
                                                if y is not None
                                            ]
                                        )
                                        - 0.05,
                                        max(
                                            [
                                                y
                                                for trace in fig.data
                                                for y in trace.y
                                                if y is not None
                                            ]
                                        )
                                        + 0.1,
                                    ],
                                }
                            ],
                            label="Reset",
                            method="relayout",
                        ),
                    ],
                    pad={"r": 10, "t": 10},
                    showactive=True,
                    x=0.05,
                    xanchor="left",
                    y=1.1,
                    yanchor="top",
                )
            ]
        )

        # Display the interactive graph
        selected_points = plotly_events(fig, click_event=True, hover_event=False)

        if selected_points:
            point_idx = selected_points[0]["pointIndex"]
            st.write(f"Selected node: {geo_solver.g.nodes[point_idx].name}")
            st.write(f"Color: {geo_solver.g.nodes[point_idx].color}")
            st.write(
                f"Neighbors: {[geo_solver.g.nodes[n].name for n in geo_solver.g.nodes[point_idx].neighbors]}"
            )

    # Display number of colors used
    used_colors = set(node.color for node in geo_solver.g.nodes)
    st.success(f"✅ Number of colors used: **{len(used_colors)}**")

    if hasattr(geo_solver.solver, "get_solver_log"):
        # Horizontal section for PySCIPOpt solver log
        st.markdown("---")
        st.subheader("PySCIPOpt Solver Log")
        solver_log_val = geo_solver.solver.get_solver_log()
        if solver_log_val:
            st.code(solver_log_val, language="text")  # preserves formatting & spacing
