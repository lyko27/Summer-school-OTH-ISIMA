#! /usr/bin/env python3

"""Template for gradient method and BFGS-SQP method
   by Stefan Koerkel 2023"""

import numpy as np
import scipy.linalg as la
import matplotlib.pyplot as plt

import functions

# -----------------------------------------------------------------------------

def backtracking( phi, phi0, dphi0,
                  alpha0=1.0, alphamin=1e-8, c1=0.5, rho=0.5, verbose=False ):
    "Backtracking linesearch"

    alpha = alpha0

    while alpha > alphamin:
        phinew = phi(alpha)
        suffdecr = phinew - ( phi0 + c1 * alpha * dphi0 )

        if verbose:
            print( "   LS: %e   % e   % e" % ( alpha, phinew, suffdecr ) )

        if suffdecr <= 0:
            return alpha

        alpha *= rho

    return -1.0

# -----------------------------------------------------------------------------

def BFGS( s, y, H ):
    # ...
    return

# -----------------------------------------------------------------------------

def GradientMethod( fun, x0, TOL=1.0e-4, kmax=2000 ):
    "Nonlinear optimization method"

    # Initialization
    n = x0.shape[0]
    log = np.empty( ( 0, 6 ), dtype=np.float64 )
    xk = np.empty( ( 0, n+1 ), dtype=np.float64 )

    # Initial value
    k = 0
    x = x0
    f, df = fun( x )
    gradf = df.reshape( n, 1 )
    deltax = np.ones( n ) * 100
    alpha = 0.0

    # Iterations
    while k <= kmax:
        # Norm of the gradient and of the step
        normdf = la.norm( df )
        normdeltax = la.norm( deltax )

        # Output log
        new = ( k, alpha, f, normdf, normdeltax, la.norm(x) )
        if not k % 20:
            print(" k   alpha           f              ||df||         " \
                  "||dx||         ||x||")
        print( "%2d   %e   % e   %e   %e   %e" % new )
        log = np.vstack( [ log, new ] )
        xk = np.vstack( [ xk, np.hstack( [ x, f ] ) ] )

        # Termination criterion
        if normdf <= TOL:
        #if normdeltax <= TOL:
            return xk, log

        # Search direction
        deltax = -gradf / normdf
        deltax = deltax.reshape( n )

        # Linesearch
        phi = lambda alpha: fun( x + alpha * deltax )[0]
        descent = df @ deltax.T
        alpha = backtracking( phi, f, descent, verbose=False )
        if alpha < 0:
            xk[-1,-1] = np.nan
            return xk, log

        # Step
        k += 1
        s = alpha * deltax
        x += s
        f, df = fun( x )
        gradf = df.reshape( n, 1 )

        # Update of the Hessian
        #...

    # No convergence
    xk[-1,-1] = np.nan
    return xk, log

# -----------------------------------------------------------------------------

def main():
    x0array = [ np.array( [ 1.5, 4 ] ),
                np.array( [ 1.5, -4 ] ),
                np.array( [ -1.5, 4 ] ),
                np.array( [ -1.5, -4 ] ) ]

    ### choose the function between these 3 : ###
      
    #fun = functions.himmelblau
    #fig0, ax0 = functions.SurfacePlot( functions.himmelblau2, (-5,5), (-5,5) )

   # fun = functions.rosenbrock
   # fig0, ax0 = functions.SurfacePlot( functions.rosenbrock2, (-2,2), (-5,5) )

    #a = 15.0
    #fun = lambda x: functions.quadratic( x, a )
    #fig0, ax0 = functions.SurfacePlot( lambda x, y:
    #                                   functions.quadratic2( x, y, a ),
    #                                   (-5,max(5,a)), (-5,5) )
    #x0array = [ np.array( [ a, 1 ] ) ]

    ind = 2
    col = [ "r", "g", "b", "m" ]
    cnt = 0

    for x0 in x0array:
        print("Initial value", x0 )

        xk, ret = GradientMethod( fun, x0 )
        #xk, ret = BFGS_SQP( fun, x0 )

        if not np.isnan( xk[-1,-1] ):
            print("Solution:", xk[-1,:] )
        else:
            print("No convergence")

        ax0.plot( xk[:,0], xk[:,1], xk[:,2],
                  color=col[cnt], marker="o", markersize=2 )

        if ind > 0:
            fig = plt.figure()
            ax = fig.add_subplot()
            ax.plot( ret[:,0], ret[:,ind], "r-" )
            ax.set_yscale("log")
            ax.grid()

        print()
        cnt += 1

    plt.show()

# -----------------------------------------------------------------------------

if __name__ == "__main__":
    main()
