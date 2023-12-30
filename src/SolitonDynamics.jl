module SolitonDynamics

# dev settings
using ExportAll

using FFTW, CUDA, Adapt
using Reexport
using OrdinaryDiffEq, DiffEqCallbacks, SteadyStateDiffEq, DiffEqGPU
import NonlinearSolve, LinearSolve
using LoopVectorization
using LinearAlgebra, RecursiveArrayTools, LazyArrays
using IntervalRootFinding, IntervalArithmetic
import JLD2
using StaticArrays
using ProgressMeter

@reexport using Parameters
import FileIO

export runsim, testsim
export Sim, SISim
export normalize, printsim

global ss_buffer = Vector{Vector{Float64}}()
global sigma2_old = Vector{Vector{Float64}}()
global sigma2_new = Vector{Vector{Float64}}()
global time_of_sigma = Vector{Float64}()

include("types.jl")
include("methods.jl")
include("arrays.jl")
include("utils.jl")
include("arrays.jl")
include("solver.jl")
include("normalization.jl")

@exportAll()

end # module CondensateDynamics
