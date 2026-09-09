from pyscipopt import Model

model = Model('BB_execise')

# We create variables
x1 = model.addVar('x1', vtype='C')
x2 = model.addVar('x2', vtype='C')
x3 = model.addVar('x3', vtype='C')

# We set objective fonction
model.setObjective(x1 + x2 + x3, 'maximize')

# create constraints
model.addCons(x1 + 3* x2 - 2*x3 <= 7)
model.addCons(x1 +3*x2 + x3 <= 3)
model.addCons(x1 - x2 + x3 <= 2)

## Lets explore by choosing x2

#model.addCons(x2 <= 0)# P1 Solution : x1, x2, x3 : 2, 0, 0 and z = 2 
#model.addCons(x2 >= 1)# P2 Solution : x1, x2, x3 : 0, 1, 0  and z = 1

# So we have an optimal solution
# voir la photo pour voir d'autre façon d'explorer mais celle là est la meilleur

# Run optimizer SCIP
model.optimize()

# get the best solution
sol = model.getBestSol()

print(f'x1 :{sol[x1]}, x2 :{sol[x2]}, x3 :{sol[x3]}')
print(f'Objective function value : {model.getObjVal()}')





