# Explication des scripts d'Optimisation Non Linéaire

Ce document explique point par point le rôle des fichiers `functions.py` et `NOP_template.py` implémentés lors de la Summer School.

---

## 1. Fichier `functions.py` (Les fonctions mathématiques à optimiser)

Ce fichier contient les "fonctions tests" classiques utilisées pour évaluer les performances des algorithmes d'optimisation. Le but de vos algorithmes sera de trouver le point `x` qui minimise ces fonctions.

*   **`himmelblau(x)`**, **`rosenbrock(x)`**, **`quadratic(x)`** : 
    Ces fonctions prennent un vecteur `x` (les coordonnées de votre position actuelle) et renvoient deux choses :
    *   `f` : La valeur de la fonction en ce point (l'altitude).
    *   `df` : Le gradient (les dérivées premières). Le gradient indique la direction dans laquelle la pente "monte" le plus. En optimisation, on va souvent dans le sens inverse du gradient pour "descendre" vers le minimum.

*   **`himmelblau2(x,y)`**, **`rosenbrock2(x,y)`**, **`quadratic2(x,y)`** :
    Ce sont des versions simplifiées des mêmes fonctions, conçues uniquement pour être dessinées en 3D. Elles ne calculent pas le gradient.

*   **`SurfacePlot(fun, ...)`** :
    Une fonction utilitaire qui utilise la bibliothèque `matplotlib` pour dessiner une jolie surface 3D (le relief) de la fonction passée en paramètre. 

*   **`if __name__ == "__main__":`** :
    C'est la partie de test du fichier. Si vous exécutez `python functions.py`, cela va afficher quelques valeurs et générer les graphiques 3D des fonctions pour que vous puissiez les visualiser.

---

## 2. Fichier `NOP_template.py` (L'algorithme de résolution)

Ce fichier est le "cerveau" de l'optimisation. "NOP" signifie *Nonlinear Optimization Programming*. Il contient un squelette d'algorithme (une descente de gradient) que vous devez probablement compléter.

*   **`backtracking(phi, phi0, dphi0, ...)`** :
    C'est l'algorithme de **Recherche Linéaire** (Line search). Une fois que l'algorithme principal a choisi une direction où aller (généralement la descente), `backtracking` sert à trouver la *longueur du pas* (appelé `alpha`). Il réduit la taille du pas (`alpha *= rho`) jusqu'à ce que la descente soit considérée comme "suffisante" (c'est ce qu'on appelle la condition d'Armijo).

*   **`BFGS(s, y, H)`** :
    C'est une fonction vide (`return`) que vous devez compléter pendant l'école d'été. BFGS est une méthode "Quasi-Newton" très célèbre. Au lieu de calculer uniquement la pente (gradient), elle essaie d'estimer la courbure de la fonction (matrice Hessienne `H`) pour prendre des chemins beaucoup plus directs vers le minimum.

*   **`GradientMethod(fun, x0, TOL, kmax)`** :
    C'est la boucle principale de votre algorithme (qui se comporte ici comme une **méthode de descente de gradient normalisée**) :
    1.  Il part d'un point de départ `x0`.
    2.  Il calcule le gradient (quelle est la pente ?).
    3.  Tant que la norme du gradient (la raideur de la pente) est supérieure à la tolérance `TOL`, il continue de chercher (`while k <= kmax`).
    4.  Il choisit une direction de recherche `deltax` (qui ici est l'opposé du gradient).
    5.  Il utilise `backtracking` pour trouver la bonne taille de pas `alpha`.
    6.  Il met à jour la position : `x = x + alpha * deltax` (il avance).
    7.  Il enregistre tout dans des tableaux (`log` et `xk`) pour pouvoir dessiner le chemin à la fin.

*   **`main()`** :
    1.  Définit quatre points de départ initiaux (les `x0array`).
    2.  Charge la fonction cible (`rosenbrock` par défaut).
    3.  Affiche le point de départ de chaque trajectoire d'optimisation (boucle `for`).
    4.  Appelle `GradientMethod(fun, x0)` ou `BFGS_SQP(fun, x0)` 
    5.  Affiche si la méthode converge et ajoute une courbe 2D à la fin pour voir la progression de l'erreur (`ax.plot(ret[:,0], ret[:,ind], "r-")`).
    
---

### En conclusion

Vous avez un ensemble d'outils complet pour tester une méthode numérique (`NOP`) face à des surfaces mathématiques complexes (`functions.py`). Le but du code `NOP` est de descendre la colline étape par étape jusqu'au trou le plus bas.