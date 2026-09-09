import streamlit as st

st.set_page_config(
    page_title="Optimization suite for summer school in Applied Optimization",
    page_icon="📊",
    layout="wide"
)

st.title("Summer school optimization suite")

st.markdown("""
This application combines several optimization tools using the **PySCIPOpt** solver. 
            
Select a module from the sidebar to begin:

* **🎨 Graph Coloring**: Solves the classic map/graph coloring problem to ensure no two adjacent nodes share the same color using MILP.
* **🚗 EV Charging Optimizer (Set Cover)**: Uses Set Covering to place charging stations based on building density and walking distances.
* **🏥 Hospital Catering (FLP)**: Solves the Facility Location Problem for Berlin hospitals, balancing fixed costs and transport logistics.
* **🧩 Sudoku Solver**: Solves Sudoku puzzles by using Integer Programming.
""")

st.info("👈 Use the sidebar to switch between different optimization models.")

# Optional: Add a decorative horizontal rule or footer
st.divider()
st.caption("Developed for the KAPT Summer School - Energy Management & Optimization")