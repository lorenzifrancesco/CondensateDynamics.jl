using Revise
using Plots, LaTeXStrings
using CondensateDynamics
import Makie, GLMakie
using HDF5, JLD2
using FFTW, CUDA, OrdinaryDiffEq
using Interpolations
using OrderedCollections

using LoopVectorization, LinearAlgebra

using ProgressBars, Colors

includet("_plot_settings.jl")
pyplot(size=(350, 220))
includet("../examples/plot_axial_evolution.jl")
includet("../examples/plot_isosurfaces.jl")
includet("visual_utils.jl")
includet("init.jl")
includet("sim_utils.jl")


```
    file signature:
```
includet("solitons.jl")


```
    file signature:
    tran.JLD2
    refl.JLD2
```
includet("lines.jl")


```
    file signature:
```
includet("tiles.jl")

includet("aux_collapse.jl")
includet("aux_gs.jl")
includet("aux_collision.jl")
includet("aux_sigma2.jl")