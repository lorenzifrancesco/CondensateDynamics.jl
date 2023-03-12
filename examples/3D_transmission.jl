using Pkg
Pkg.activate(".")

using CondensateDynamics, OrdinaryDiffEq, LSODA
import CondensateDynamics.V
using CUDA
using LaTeXStrings, Plots
import GR
using CUDA.CUFFT
import Makie, GLMakie

# ================ plotting functions
function dense(phi)
    psi = xspace(phi,sim)
    density = abs2.(psi)
    pmax = maximum(density)
    if pmax == 0
        throw("Maximum density is null")
    end
    return density/pmax
end

function isosurface_animation(sol,Nt, sim;file="3Devolution.gif",framerate=3)
    saveto=joinpath("media",file)
    scene = Makie.Scene()
    tindex = Makie.Observable(1)
    iter = [Array(xspace(sol[k], sim)) for k in 1:Nt]
    iter = [abs2.(iter[k]) for k in 1:Nt]
    fig = Makie.volume(Makie.@lift(iter[$tindex]/maximum(iter[$tindex])),
                        algorithm =:iso,
                        isovalue=0.1,
                        isorange=0.1,
                        transparency=true
    )

    R = 180
    # eyeat = Makie.Vec3f0(R,0,0)
    # lookat = Makie.Vec3f0(-50,-50,0)
    # cam = Makie.cameracontrols(scene)
    # Makie.update_cam!(scene, eyeat, lookat)

    Makie.record(scene, saveto, 1:Nt; framerate=framerate) do i
        tindex[] = i
    end
    return
end

function isosurface(sol)
    scene = Makie.Scene()
    tindex = Makie.Observable(1)
    psol = Array(abs2.(xspace(sol, sim)))
    scene = Makie.volume(psol/maximum(psol),
                        algorithm =:iso,
                        isovalue=0.1,
                        isorange=0.1,
    )
    display(scene)
    return
end

gr()
GR.usecolorscheme(1)

# =================== simulation settings
L = (40.0,40.0,40.0)
N = (128,128,128)
sim = Sim{length(L), CuArray{Complex{Float64}}}(L=L, N=N)

# =================== physical parameters 
@unpack_Sim sim
g = -0.587 * 2*pi
equation = GPE_3D
iswitch = 1
x = Array(X[1])
y = Array(X[2])
z = Array(X[3])
dV= volume_element(L, N)
reltol = 1e-3
tf = 1
Nt = 30
t = LinRange(ti,tf,Nt)
# nfiles = true
maxiters = 2000
vv = 0.0
tmp = [exp(-(x^2+y^2+z^2)/2) * exp(-im*z*vv) for x in x, y in y, z in z]
psi_0 = CuArray(tmp)

psi_0 .= psi_0 / sqrt(sum(abs2.(psi_0) * dV))
initial_state = psi_0
kspace!(psi_0, sim)
alg = BS3()
tmp = [1/2*(x^2+y^2+ 3*z^2) for x in x, y in y, z in z]
V0 = CuArray(tmp)
#V(x,y,z,t) = 1/2 * (x^2+y^2+z^2)
@pack_Sim! sim


# ===================== simulation
sol = runsim(sim; info=false)
final = sol[end]

# =================== plotting and collect 
xspace!(final, sim)
xspace!(psi_0, sim)
final = Array(sum(abs2.(sol[end]), dims=(2, 3)))
psi_0 = Array(sum(abs2.(psi_0), dims=(2, 3)))

@info "final distribution norm squared: " ns(final, sim)

# p = plot(real.(Array(x)), abs2.(psi_0[:, 1, 1]), label="initial")
# #plot!(p, real.(Array(x)), abs2.(final[:, 1, 1]), label="final")
# display(p)

# isosurface animation 
# scene = Makie.volume(Array(abs2.(sol[1])/(maximum(abs2.(sol[1])))),
# algorithm = :iso,
# color = (:blue,0.25),
# isovalue=3f0(.15)
# )
#isosurface(sol[1])
@info "Building animation..."
isosurface_animation(sol,length(sol), sim; framerate=5)
@info "Completed."