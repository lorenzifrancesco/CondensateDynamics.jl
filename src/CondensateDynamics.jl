module CondensateDynamics

using FFTW, CUDA
using Parameters
using Reexport
using LinearAlgebra
using OrdinaryDiffEq: ODEProblem, solve
using LazyArrays
import OrdinaryDiffEq
import DiffEqGPU

@reexport using Parameters
@reexport using JLD2
import FileIO

export runsim, testsim
export Sim, SISim 
export normalize, printsim

include("methods.jl")
include("types.jl")
include("arrays.jl")
include("solver.jl")
include("normalization.jl")

end # module CondensateDynamics