#! /usr/bin/env python3

"""Implementation of the Himmelblau, Rosenbrock and Quadratic test-function
   with first derivatives
   by Stefan Koerkel 2022"""

import numpy as np
import matplotlib
import matplotlib.pyplot as plt

# -----------------------------------------------------------------------------

def himmelblau( x ):
    "Himmelblau function"
    t1 = x[0]**2 + x[1] - 11.0
    dt1 = np.array( [ 2 * x[0], 1.0 ] )
    t2 = x[0] + x[1]**2 - 7.0
    dt2 = np.array( [ 1.0, 2 * x[1] ] )
    f = t1**2 + t2**2
    df = 2 * t1 * dt1 + 2 * t2 * dt2
    return f, df


def rosenbrock( x ):
    "Rosenbrock function"
    t1 = 1 - x[0]
    dt1 = np.array( [ -1.0, 0.0 ] )
    t2 = x[1] - x[0]**2
    dt2 = np.array( [ -2 * x[0], 1.0 ] )
    f = t1**2 + 100 * t2**2
    df = 2.0 * t1 * dt1 + 200 * t2 * dt2
    return f, df


def quadratic( x, a=1.5 ):
    "Quadratic test-function"
    t1 = x[0]**2
    dt1 = np.array( [ 2 * x[0], 0.0 ] )
    t2 = a * x[1]**2
    dt2 = np.array( [ 0.0, 2 * a * x[1] ] )
    f = t1 + t2
    df = dt1 + dt2
    return f, df

# -----------------------------------------------------------------------------

def himmelblau2( x, y ):
    "Himmelblau function for 2D-plot"
    return (x**2 + y - 11)**2 + (x + y**2 - 7)**2


def rosenbrock2( x, y ):
    "Rosenbrock function for 2D-plot"
    return (1 - x)**2 + 100 * (y - x**2)**2


def quadratic2( x, y, a=1.5 ):
    "Quadratic test-function for 2D-plot"
    return x**2 + a * y**2

# -----------------------------------------------------------------------------

def SurfacePlot( fun, xint=(-4,4), yint=(-4,4), step=0.01 ):
    "2D surface-plot"
    x = np.arange( xint[0], xint[1], step )
    y = np.arange( yint[0], yint[1], step )
    x, y = np.meshgrid( x, y )
    z = fun( x, y )

    fig = plt.figure()
    ax = fig.add_subplot( projection="3d" )
    surf = ax.plot_surface( x, y, z, \
                            cmap=matplotlib.cm.coolwarm, \
                            linewidth=0, antialiased=False, alpha=0.8 )
    fig.colorbar( surf, shrink=0.5, aspect=10 )
    return fig, ax

# -----------------------------------------------------------------------------

if __name__ == "__main__":
    # Test call
    for x in [ np.array( [ -1.5, -4 ] ), \
               np.array( [ -1.5, 4 ] ), \
               np.array( [ 1.5, -4 ] ), \
               np.array( [ 1.5, 4 ] ), \
               np.array( [ 1.0, 1.0 ] ) ]:
        print( "x =", x )
        print( "Himmelblau:", himmelblau( x ) )
        print( "Rosenbrock:", rosenbrock( x ) )
        print( "Quadratic: ", quadratic( x ) )
        print()

    SurfacePlot( himmelblau2, (-4,4), (-4,4) )
    plt.title( "Himmelblau function" )
    #plt.savefig( "Himmelblau.png" )
    plt.show()

    SurfacePlot( rosenbrock2, (-2,2), (-4,4) )
    plt.title( "Rosenbrock function" )
    #plt.savefig( "Rosenbrock.png" )
    plt.show()

    SurfacePlot( quadratic2, (-4,4), (-4,4) )
    plt.title( "Quadratic test-function" )
    #plt.savefig( "Quadratic.png" )
    plt.show()
