import streamlit as st
import pandas as pd
import geopandas as gpd
import matplotlib.pyplot as plt
from matplotlib.offsetbox import OffsetImage, AnnotationBbox
from pyscipopt import Model, quicksum
from scipy.spatial.distance import cdist
from pathlib import Path
import io
import sys

# -----------------------------
# Streamlit App Configuration
# -----------------------------
st.set_page_config(page_title="Hospital catering FLP", layout="wide")

st.title("Facility location problem for hospital catering")
st.markdown(
    """
    Configure parameters and run the optimization to find the best locations for catering facilities.
    """
)

# -----------------------------
# Sidebar: User configuration
# -----------------------------
st.sidebar.header("Configuration")

transport_costs = st.sidebar.number_input(
    "Transport cost per km", min_value=0.0, value=5.0, step=0.5
)
max_open_locations = st.sidebar.slider(
    "Maximum number of open catering locations", min_value=1, max_value=15, value=7
)

# -----------------------------
# File paths (read automatically)
# -----------------------------
DATA_DIR = Path("datasets")
MAP_DIR = Path("maps/berlin")
IMG_DIR = Path("img")

from pathlib import Path
ROOT_DIR = Path(__file__).parent.parent
FILE_HOSPITALS = ROOT_DIR / 'flp' / "datasets" / "hospitals_berlin.csv"
FILE_CATERING = ROOT_DIR / 'flp' / "datasets" / "catering_locations.csv"
BERLIN_SHAPEFILE = ROOT_DIR / 'flp' / "maps" / "berlin" / "berlin_map.shp"
HOSPITAL_ICON = ROOT_DIR / 'flp' / "img" / "hospitals_berlin.png"

# -----------------------------
# Helper functions
# -----------------------------
def load_csv(file_path: Path) -> pd.DataFrame:
    """
    Load a CSV file with specific formatting.

    This helper function reads a CSV file that uses semicolons as separators
    and commas as decimal markers, which is common in European datasets.

    :param file_path: Path to the CSV file.
    :type file_path: pathlib.Path

    :return: Loaded data as a pandas DataFrame.
    :rtype: pandas.DataFrame
    """
    return pd.read_csv(file_path, sep=';', decimal=',', encoding='cp1252')


def compute_distance_matrix(hospitals: pd.DataFrame, catering: pd.DataFrame) -> pd.DataFrame:
    """
    Compute pairwise distances between hospitals and catering locations.

    The function calculates the Euclidean distance between geographic coordinates
    (latitude, longitude) and scales it by Earth's radius to approximate distances in kilometers.

    :param hospitals: DataFrame containing hospital locations with columns
                      ['latitude', 'longitude'].
    :type hospitals: pandas.DataFrame
    :param catering: DataFrame containing catering locations with columns
                     ['latitude', 'longitude'].
    :type catering: pandas.DataFrame

    :return: Distance matrix of shape (n_hospitals, n_catering_locations).
    :rtype: numpy.ndarray
    """
    hosp_coords = hospitals[['latitude', 'longitude']].to_numpy()
    cat_coords = catering[['latitude', 'longitude']].to_numpy()
    return cdist(hosp_coords, cat_coords, metric='euclidean') * 6371


def create_model(df_hospitals: pd.DataFrame,
                 df_catering: pd.DataFrame,
                 distances,
                 max_locations: int,
                 transport_cost: float):
    """
    Create and formulate the Facility Location Problem (FLP) as a MILP.

    The model determines which catering facilities to open and assigns each hospital
    to exactly one open facility, while minimizing total costs.

    The objective consists of:
        - Transportation costs (distance * cost per km)
        - Fixed opening costs for catering locations

    Constraints include:
        - Each hospital must be assigned to exactly one catering location
        - Capacity limits for each catering facility
        - Maximum number of open facilities

    :param df_hospitals: DataFrame with hospital data, including demand information.
    :type df_hospitals: pandas.DataFrame
    :param df_catering: DataFrame with catering facility data, including capacities and fixed costs.
    :type df_catering: pandas.DataFrame
    :param distances: Matrix of distances between hospitals and catering locations.
    :type distances: numpy.ndarray
    :param max_locations: Maximum number of facilities that can be opened.
    :type max_locations: int
    :param transport_cost: Cost per kilometer for transportation.
    :type transport_cost: float

    :return: Tuple containing the model and decision variables.
    :rtype: tuple(pyscipopt.Model, dict, dict)
    """
    model = Model("FLP")

    # Binary variables: whether a catering location is opened
    catering_vars = {
        loc_idx: model.addVar(name=f"Location_{loc_idx}", vtype="B")
        for loc_idx in df_catering.index
    }

    # Binary assignment variables: hospital -> catering location
    assign_vars = {
        (hosp_idx, loc_idx): model.addVar(
            name=f"Hospital_{hosp_idx}_Location_{loc_idx}", vtype="B"
        )
        for hosp_idx in df_hospitals.index
        for loc_idx in df_catering.index
    }

    # Objective function: transportation + fixed costs
    model.setObjective(
        quicksum(assign_vars[(hosp_idx, loc_idx)] * distances[i, j] * transport_cost
                 for i, hosp_idx in enumerate(df_hospitals.index)
                 for j, loc_idx in enumerate(df_catering.index)) +
        quicksum(catering_vars[loc_idx] * df_catering.loc[loc_idx, 'fixed_costs']
                 for loc_idx in df_catering.index),
        "minimize"
    )

    # Each hospital must be assigned to exactly one location
    for hosp_idx in df_hospitals.index:
        model.addCons(
            quicksum(assign_vars[(hosp_idx, loc_idx)]
                     for loc_idx in df_catering.index) == 1
        )

    # Capacity constraints for catering locations
    for loc_idx in df_catering.index:
        model.addCons(
            quicksum(
                assign_vars[(hosp_idx, loc_idx)] *
                df_hospitals.loc[hosp_idx, 'nr_beds'] *
                (df_hospitals.loc[hosp_idx, 'avg_bed_occupancy'] / 100)
                for hosp_idx in df_hospitals.index
            )
            <= catering_vars[loc_idx] *
            df_catering.loc[loc_idx, 'capacity']
        )

    # Limit the number of open facilities
    model.addCons(
        quicksum(catering_vars[loc_idx] for loc_idx in df_catering.index) <= max_locations
    )

    return model, catering_vars, assign_vars



def visualize_solution(df_hospitals: pd.DataFrame,
                       df_catering: pd.DataFrame,
                       model,
                       catering_vars: dict,
                       assign_vars: dict) -> None:
    """
    Visualize the optimized facility location solution on a map.

    Hospitals are displayed as icons, while catering locations are shown
    as squares (open) or crosses (closed). Assignment relationships are
    illustrated with dashed lines.

    :param df_hospitals: DataFrame containing hospital data.
    :type df_hospitals: pandas.DataFrame
    :param df_catering: DataFrame containing catering location data.
    :type df_catering: pandas.DataFrame
    :param model: Solved optimization model.
    :type model: pyscipopt.Model
    :param catering_vars: Binary decision variables for facility opening.
    :type catering_vars: dict
    :param assign_vars: Binary assignment variables.
    :type assign_vars: dict

    :return: None
    :rtype: None
    """
    gdf_hospitals = gpd.GeoDataFrame(
        df_hospitals,
        geometry=gpd.points_from_xy(
            df_hospitals['longitude'],
            df_hospitals['latitude']
        ),
        crs='EPSG:4326'
    )

    gdf_berlin = gpd.read_file(BERLIN_SHAPEFILE)
    icons = [OffsetImage(plt.imread(HOSPITAL_ICON), zoom=0.015) for _ in range(len(gdf_hospitals))]
    colors = plt.get_cmap('tab20', len(df_catering))

    fig, ax = plt.subplots(figsize=(14, 8))
    gdf_berlin.plot(ax=ax, color='green', alpha=0.2)

    # Plot hospitals
    for i, icon in enumerate(icons):
        ax.add_artist(AnnotationBbox(icon, (gdf_hospitals.geometry.x[i], gdf_hospitals.geometry.y[i]), frameon=False))

    # Plot catering locations
    for loc_idx in df_catering.index:
        lon, lat = df_catering.loc[loc_idx, ['longitude', 'latitude']]
        if model.getVal(catering_vars[loc_idx]) > 0.5:
            color = colors(loc_idx)
            ax.scatter(lon, lat, color=color, s=100, marker='s', label=df_catering.loc[loc_idx, 'name'])
            for hosp_idx in df_hospitals.index:
                if model.getVal(assign_vars[(hosp_idx, loc_idx)]) > 0.5:
                    x_h, y_h = gdf_hospitals.geometry.x[hosp_idx], gdf_hospitals.geometry.y[hosp_idx]
                    ax.plot([lon, x_h], [lat, y_h], color=color, linestyle='--', linewidth=0.8)
        else:
            ax.scatter(lon, lat, color='black', s=100, marker='x',
                       label=f"{df_catering.loc[loc_idx, 'name']} (closed)")

    ax.legend(loc='upper left', bbox_to_anchor=(1, 1))
    ax.set_title('Optimal catering locations for hospitals in Berlin', fontsize=15)
    ax.set_xlabel('Longitude')
    ax.set_ylabel('Latitude')
    st.pyplot(fig)


# -----------------------------
# Run optimization
# -----------------------------
if st.button("Run Optimization"):

    # Load files automatically
    df_hospitals = load_csv(FILE_HOSPITALS)
    df_catering = load_csv(FILE_CATERING)

    distances = compute_distance_matrix(df_hospitals, df_catering)
    model, catering_vars, assign_vars = create_model(df_hospitals, df_catering,
                                                     distances, max_open_locations, transport_costs)

    # Redirect console output to Streamlit
    st_text = st.empty()
    old_stdout = sys.stdout
    sys.stdout = buffer = io.StringIO()

    model.optimize()

    sys.stdout = old_stdout
    st_text.text(buffer.getvalue())

    if model.getStatus() == 'optimal':
        st.success("Optimal solution found!")
        visualize_solution(df_hospitals, df_catering, model, catering_vars, assign_vars)
    else:
        st.error("No optimal solution found.")
