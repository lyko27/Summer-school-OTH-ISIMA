import streamlit as st
import pandas as pd
import numpy as np
from pyscipopt import Model, quicksum, SCIP_PARAMSETTING
import matplotlib.pyplot as plt
import random

# ---------------------------------------------------
# Page setup
# ---------------------------------------------------
st.set_page_config(page_title="Sudoku Solver")

# Remove column menu (three dots)
st.markdown(
    """
    <style>
    button[data-testid="stColumnActionButton"] {
        display: none;
    }
    </style>
    """,
    unsafe_allow_html=True
)

# ---------------------------------------------------
# Sudoku MIP Model
# ---------------------------------------------------
def create_model(init_vals):
    """
    Create a PySCIPOpt model for Sudoku.

    Args:
        init_vals (dict): initial values {(row,col): value}

    Returns:
        m (Model): PySCIPOpt model
        y (dict): decision variables {(row,col,value): var}
    """
    m = Model("Sudoku")
    #m.setPresolve(SCIP_PARAMSETTING.OFF)

    # Binary variables y[r,c,v] == 1 if cell (r,c) has value v
    y = {
        (r, c, v): m.addVar(vtype="B")
        for r in range(1,10)
        for c in range(1,10)
        for v in range(1,10)
    }

    # Initial clues
    for ((r,c),v) in init_vals.items():
        m.addCons(y[r,c,v] == 1)

    # One number per cell
    for r in range(1,10):
        for c in range(1,10):
            m.addCons(quicksum(y[r,c,v] for v in range(1,10)) == 1)

    # Each number appears once per row
    #################### TODO ####################
    ###### Add constraint that ensures that each
    ###### number appears exactly once per row
    ##############################################

    for r in range(1,10):
        for v in range(1,10):
            m.addCons(quicksum(y[r,c,v] for c in range(1,10)) == 1)

    # Each number appears once per column
    #################### TODO ####################
    ###### Add constraint that ensures that each
    ###### number appears exactly once per column
    ##############################################

    for c in range(1,10):
        for v in range(1,10):
            m.addCons(quicksum(y[r,c,v] for r in range(1,10)) == 1)

    # Each number appears once per 3x3 box
    #################### TODO ####################
    ###### Add constraint that ensures that each
    ###### number appears exactly once per 3x3 box
    ##############################################

    for i in [1, 4, 7]:
        for j in [1, 4, 7]:
            for v in range(1, 10):
                m.addCons(quicksum(y[r, c, v] for r in range(i, i+3) for c in range(j, j+3)) == 1)



    return m,y

# ---------------------------------------------------
# Solver
# ---------------------------------------------------
def solve_sudoku(init_vals):
    """
    Solve a Sudoku puzzle using MIP.

    Args:
        init_vals (dict): initial values {(row,col): value}

    Returns:
        grid (np.array): solved 9x9 grid or None if infeasible
    """
    m,y = create_model(init_vals)
    m.optimize()

    if m.getStatus() != "optimal":
        return None

    solution = [k for k in y if m.getVal(y[k]) > 0.99]
    grid = np.zeros((9,9), dtype=int)
    for (r,c,v) in solution:
        grid[r-1,c-1] = v

    return grid

# ---------------------------------------------------
# Random Sudoku Generator
# ---------------------------------------------------
def generate_random_sudoku(num_clues):
    """
    Generate a random valid Sudoku puzzle with a given number of clues.

    Args:
        num_clues (int): number of filled cells

    Returns:
        puzzle (np.array): 9x9 puzzle grid with zeros for empty cells
    """
    m, y = create_model({})
    m.optimize()

    solution = [k for k in y if m.getVal(y[k]) > 0.99]
    grid = np.zeros((9,9), dtype=int)
    for (r,c,v) in solution:
        grid[r-1,c-1] = v

    # Randomly remove cells to leave only num_clues
    positions = [(r,c) for r in range(9) for c in range(9)]
    random.shuffle(positions)
    remove = 81 - num_clues
    for i in range(remove):
        r,c = positions[i]
        grid[r,c] = 0

    return grid

# ---------------------------------------------------
# Convert DataFrame grid to model input
# ---------------------------------------------------
def grid_to_initvals(df):
    """
    Convert editable grid to initial values dict for MIP.

    Args:
        df (pd.DataFrame): editable grid

    Returns:
        init_vals (dict): {(row,col): value}
    """
    init_vals = {}
    for r in range(9):
        for c in range(9):
            val = str(df.iat[r,c]).strip()
            if val != "":
                try:
                    v = int(val)
                    if 1 <= v <= 9:
                        init_vals[(r+1,c+1)] = v
                except:
                    pass
    return init_vals

# ---------------------------------------------------
# Style Sudoku grid for editable display
# ---------------------------------------------------
def style_sudoku(df):
    """
    Apply CSS borders to mimic Sudoku 3x3 boxes.

    Args:
        df (pd.DataFrame): grid

    Returns:
        pd.io.formats.style.Styler: styled grid
    """
    styles = []

    # Thick right border every 3 columns
    for c in range(9):
        border = "3px solid black" if (c+1)%3==0 else "1px solid black"
        styles.append({
            "selector": f"th:nth-child({c+1})",
            "props": [("border-right", border)]
        })

    # Thick bottom border every 3 rows
    for r in range(9):
        border = "3px solid black" if (r+1)%3==0 else "1px solid black"
        styles.append({
            "selector": f"tbody tr:nth-child({r+1}) td",
            "props": [("border-bottom", border)]
        })

    # Thin top/left for all cells
    styles.append({
        "selector": "td",
        "props": [("border-left", "1px solid black"),
                  ("border-top", "1px solid black")]
    })

    return df.style.set_table_styles(styles)

# ---------------------------------------------------
# Streamlit UI
# ---------------------------------------------------
st.title("Sudoku Solver using Integer Programming")
st.sidebar.header("Puzzle Settings")
num_clues = st.sidebar.slider("Number of initial clues", 17, 60, 30)

# Initialize editable grid in session state
if "grid" not in st.session_state:
    st.session_state.grid = pd.DataFrame(
        [[""]*9 for _ in range(9)],
        columns=[1,2,3,4,5,6,7,8,9],
        index=[1,2,3,4,5,6,7,8,9]
    )

# Generate puzzle button
if st.button("Generate Sudoku"):
    puzzle = generate_random_sudoku(num_clues)
    df = pd.DataFrame(
        puzzle,
        columns=[1,2,3,4,5,6,7,8,9],
        index=[1,2,3,4,5,6,7,8,9]
    )
    df = df.replace(0, "")
    st.session_state.grid = df

# Display editable Sudoku grid with row numbers
st.subheader("Sudoku grid")
grid = st.data_editor(
    st.session_state.grid,
    column_config={i: st.column_config.TextColumn(label=str(i), width="small") for i in range(1,10)},
    num_rows="fixed",
    hide_index=False,
    key="sudoku_editor",
)

# Solve Sudoku button
if st.button("Solve Sudoku"):
    init_vals = grid_to_initvals(grid)
    with st.spinner("Solving..."):
        solution = solve_sudoku(init_vals)
    if solution is not None:
        st.subheader("Solution")
        # Plot solution with 3x3 boxes
        fig, ax = plt.subplots(figsize=(5,5))
        ax.imshow([[0]*9]*9, cmap="Greens", extent=[0,9,0,9])
        for i in range(10):
            lw = 2 if i%3==0 else 1
            ax.axhline(i, color="black", linewidth=lw)
            ax.axvline(i, color="black", linewidth=lw)
        for r in range(9):
            for c in range(9):
                if solution[r,c] != 0:
                    ax.text(c+0.5,8.5-r,str(solution[r,c]),
                            ha="center", va="center", fontsize=16)
        ax.axis("off")
        st.pyplot(fig)
    else:
        st.error("No feasible solution found.")

st.markdown("---")
st.caption("Sudoku Solver using PySCIPOpt and Streamlit")