## ==== Arrays


V(x, t) = 0.0
V(x, y, t) = 0.0
V(x, y, z, t) = 0.0


xvec(L, N) = LinRange(-L / 2, L / 2, N + 1)[1:end-1]

function kvec(L, N)
  # @assert iseven(N)
  # nk = 0:Int(N/2)
  # k = [nk[1:end-1];-reverse(nk[2:end])]*2*π/λ
  k::AbstractFFTs.Frequencies{Float64} = fftfreq(N) * N * 2 * π / L
  return k
end

function xvecs(L::Tuple, N::Tuple)
  dims = length(N)
  X = Vector{LinRange{Float64,Int64}}(undef, (dims))
  @inbounds for idx in eachindex(X)
    X[idx] = xvec(L[idx], N[idx])
  end
  X
end

function kvecs(L, N)
  dims = length(N)
  K = Vector{AbstractFFTs.Frequencies{Float64}}(undef, (dims))
  for idx in eachindex(K)
    K[idx] = kvec(L[idx], N[idx])
  end
  K
end

function k2(K, A)
  kind = Iterators.product(K...)
  tmp::A = map(k -> sum(abs2.(k)), kind)
  return tmp
end

function volume_element(L, N)
  dV = 1
  for i in eachindex(L)
    dV *= L[i] / (N[i])
  end
  return dV
end

function makearrays(L, N)
  @assert length(L) == length(N)
  X = xvecs(L, N)
  K = kvecs(L, N)
  dX = Float64[]
  dK = Float64[]
  for j ∈ eachindex(X)
    x = X[j]
    k = K[j]
    dx = x[2] - x[1]
    dk = k[2] - k[1]
    push!(dX, dx)
    push!(dK, dk)
  end
  dX = dX |> Tuple
  dK = dK |> Tuple
  return X, K, dX, dK
end


function crandn_array(N, T)
  a::T = rand(N...) |> complex
  return a
end


function crandnpartition(N, A)
  a = crandn_array(N, A)
  args = []
  for j = 1:N
    push!(args, a)
  end
  return ArrayPartition(args...)
end

## ==== Transforms
# --> into transforms
function dfft(x, k)
  dx = x[2] - x[1]
  Dx = dx
  Dk = 1 / Dx
  return Dx, Dk
end

# TODO 2
# --> into nsk, ns
function measures(L, N)
  dX = L ./ (N)
  dK = 1 ./ (dX .* N)
  return prod(dX), prod(dK)
end


function dfftall(X, K)
  M = length(X)
  DX = zeros(M)
  DK = zeros(M)
  for i ∈ eachindex(X)
    DX[i], DK[i] = dfft(X[i], K[i])
  end
  return DX, DK
end


function definetransforms(funcs, args, meas; kwargs=nothing)
  trans = []
  if kwargs === nothing
    for (fun, arg) in zip(funcs, args)
      push!(trans, fun(arg...))
    end
  else
    for (fun, arg) in zip(funcs, args)
      push!(trans, fun(arg..., flags=kwargs))
    end
  end
  return meas .* trans
end

function makeT(X, K, T::Type{Array{ComplexF64}}; flags=FFTW.MEASURE)
  FFTW.set_num_threads(1)
  D = length(X)
  N = length.(X)
  DX, DK = dfftall(X, K)
  dμx = prod(DX)
  dμk = prod(DK)
  trans = (plan_fft, plan_fft!, plan_ifft, plan_ifft!)
  meas = (dμx, dμx, dμk, dμk)
  psi_test::T = crandn_array(N, T)
  args = ((psi_test,), (psi_test,), (psi_test,), (psi_test,))
  # Txk, Txk!, Tkx, Tkx! = definetransforms(trans, args, meas; kwargs = flags)
  Txk = dμx * plan_fft(psi_test, flags=flags)
  Txk! = dμx * plan_fft!(psi_test, flags=flags)
  Tkx = dμk * plan_ifft(psi_test, flags=flags)
  Tkx! = dμk * plan_ifft!(psi_test, flags=flags)
  trans_library = Transforms{T}(Txk, Txk!, Tkx, Tkx!)
  trans_library
end


function makeT(X, K, T::Type{CuArray{ComplexF64}}; flags=FFTW.MEASURE)
  D = length(X)
  N = length.(X)
  DX, DK = dfftall(X, K)
  dμx = prod(DX)
  dμk = prod(DK)
  psi_test = CuArray(ones(N...)) |> complex
  trans = (
    CUDA.CUFFT.plan_fft,
    CUDA.CUFFT.plan_fft!,
    CUDA.CUFFT.plan_ifft,
    CUDA.CUFFT.plan_ifft!,
  )
  meas = (dμx, dμx, dμk, dμk)
  args = ((psi_test,), (psi_test,), (psi_test,), (psi_test,))
  Txk, Txk!, Tkx, Tkx! = definetransforms(trans, args, meas)
  return GPUTransforms{T}(Txk, Txk!, Tkx, Tkx!)
end

function xspace(ϕ::AbstractArray, sim::Sim)
  return sim.T.Tkx * ϕ
end

function xspace!(ψ, sim)
  @unpack T = sim
  T.Tkx! * ψ
  return nothing
end

function kspace(ψ, sim)
  @unpack T = sim
  return T.Txk * ψ
end

function kspace!(ψ, sim)
  @unpack T = sim
  T.Txk! * ψ
  return nothing
end

function g2gamma(g::Float64, eq::EquationType)
  if eq == GPE_3D
    return -g / (4 * pi)
  else
    return -g / 2
  end
end

function gamma2g(gamma::Float64, eq::EquationType)
  if eq == GPE_3D
    return -gamma * (4 * pi)
  else
    return -2 * gamma
  end
end