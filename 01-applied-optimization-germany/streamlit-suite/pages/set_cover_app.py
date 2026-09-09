import streamlit as st
import sys
from pathlib import Path

# Ensure the root directory is in the path so we can find 'set_cover'
root_path = Path(__file__).parent.parent
if str(root_path) not in sys.path:
    sys.path.append(str(root_path))

from streamlit_folium import st_folium
from set_cover.solver import EvPlacementSolver
from set_cover import config
from set_cover.visualization import create_interactive_map, visualize_coverage, create_static_plot

def main():
   
    st.title("⚡ EV charging station optimizer")

    # Sidebar inputs
    st.sidebar.header("Optimization Settings")
    city = st.sidebar.text_input("District Name", config.DISTRICT_NAME)
    max_dist = st.sidebar.slider("Walking Distance (meters)", 200, 2000, config.MAX_WALKING_DISTANCE_METERS)
    spacing = st.sidebar.slider("Grid Spacing (meters)", 100, 1000, config.GRID_SPACING_METERS)
    
    # Sync config with UI
    config.DISTRICT_NAME = city
    config.MAX_WALKING_DISTANCE_METERS = max_dist
    config.GRID_SPACING_METERS = spacing

    if st.sidebar.button("Run Optimizer"):
        solver = EvPlacementSolver()

        with st.status("Processing spatial data...", expanded=True) as status:
            st.write("Fetching district boundary and buildings...")
            solver.load_data()
            st.write("Running optimization solver...")
            solver.run()
            status.update(label="Optimization Complete!", state="complete")

        solution = solver.get_result()

        if solution is not None:
            st.subheader("Interactive Solution Map")
            
            # Metrics
            total = len(solution)
            new = len(solution[~solution.get("existing", False)])
            
            m_col1, m_col2 = st.columns(2)
            m_col1.metric("Total Stations (Existing + New)", total)
            m_col2.metric("New Recommended Stations", new)
            
            # Render Folium Map
            st.subheader("Interactive Coverage Map")
            folium_map = create_interactive_map(
                solution, solver.demand_points, solver.district_poly, solver.coverage_matrix
            )
            st_folium(
                folium_map, 
                width=1000, 
                height=600, 
                # Unique key prevents duplicate element errors
                key=f"map_coverage_{config.DISTRICT_NAME.replace(' ', '_')}",
                returned_objects=[] 
            )
            
            # Static plot in expander
            with st.expander("View Static Summary Plot"):
                fig = create_static_plot(solution, solver.demand_points)
                st.pyplot(fig)

            # Debug Coverage Map
            coverage_map = visualize_coverage(
                solver.demand_points,
                solver.candidates,
                solver.coverage_matrix
            )

            st.subheader("Coverage Analysis Map")
            st_folium(
                coverage_map,
                width=700,
                height=500,
                key="coverage_debug_map", 
                returned_objects=[]
            )
        else:
            st.error("Could not find a solution. Try increasing the walking distance.")

if __name__ == "__main__":
    main()