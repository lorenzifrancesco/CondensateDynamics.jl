"""
Time evolution in xspace 3D
"""
function nlin!(dpsi,psi,sim::Sim{3, CuArray{ComplexF64}},t)
   @unpack g,X,V0,iswitch,dV,Vol,mu = sim; x = X[1]; y = X[2]; z = X[3]
   dpsi .= psi
   mu_im = 0.0
   if iswitch == -im 
      mu_im = chempotk(psi, sim) # wainting for a more efficient implementation
   end
   xspace!(dpsi, sim)
   @. dpsi *= -im * (V0 + V.(x, y, z, t) + g*abs2(dpsi)) + mu_im
   kspace!(dpsi, sim)
   return nothing
end


"""
Time evolution in kspace 3D 
"""
function propagate!(dpsi, psi, sim::Sim{3, CuArray{ComplexF64}}, t; info=false)
   @unpack ksquared,iswitch,X,mu,gamma = sim; x = X[1]
   nlin!(dpsi,psi,sim,t)
   #@. dpsi = (1.0 - im*gamma)*(-im*(1/2*ksquared - mu)*psi + dpsi)
   @. dpsi += -im*(1/2*ksquared)*psi
   #@info nsk(psi, sim)
   return nothing
end


"""
Time evolution in xspace
"""
function nlin!(dpsi,psi,sim::Sim{1, Array{ComplexF64}},t)
   @unpack ksquared,g,X,V0,iswitch,dV,Vol,mu,equation,sigma2 = sim; x = X[1]
   dpsi .= psi
   mu_im = 0.0
   if iswitch == -im
      mu_im = chempotk(psi, sim) # wainting for a more efficient implementation
   end
   xspace!(dpsi,sim)
   if equation == GPE_1D
      @. dpsi = (exp(dt/2 * -im*iswitch* (V0 + V(x, t) + g*abs2(psi)))-1) * dpsi + mu_im
   elseif equation == NPSE
      nonlinear = g*abs2.(dpsi) ./sigma2.(dpsi) + (1 ./(2*sigma2.(dpsi)) + 1/2*sigma2.(dpsi))
      @. dpsi = (exp(dt/2*-im*iswitch* (V0 + V(x, t) + nonlinear))-1) * dpsi + mu_im
      #@info g*maximum(abs2.(dpsi))
   end
   kspace!(dpsi,sim)
   return nothing
end


"""
Time evolution in kspace
"""
function propagate!(dpsi, psi, sim::Sim{1, Array{ComplexF64}}, t; info=false)
   @unpack ksquared, iswitch, dV, Vol,mu,gamma = sim
      nlin!(dpsi,psi,sim,t)
      #    @. dϕ = -im*(1.0 - im*γ)*(dϕ + (espec - μ)*ϕ)
      @. dpsi = (exp(dt/2 * (1.0 - im*gamma)*(-im*(1/2*ksquared - mu))) - 1) * psi
   return nothing
end


# ============== ManualSplitStep methods, improved with exp
"""
Time evolution in xspace
"""
function nlin_manual!(dpsi,psi,sim::Sim{1, Array{ComplexF64}},t)
   @unpack ksquared,g,X,V0,dV,Vol,mu,equation,sigma2,dt,iswitch = sim; x = X[1]
   xspace!(psi,sim)
   if equation == GPE_1D
      @. psi = exp(dt/2 * -im*iswitch* (V0 + V(x, t) + g*abs2(psi))) * psi
   elseif equation == NPSE
      nonlinear = g*abs2.(dpsi) ./sigma2.(dpsi) + (1 ./(2*sigma2.(dpsi)) + 1/2*sigma2.(dpsi))
      @. psi = exp(dt/2*-im*iswitch* (V0 + V(x, t) + nonlinear)) * psi
   end
   kspace!(psi,sim)
   return nothing
end


"""
Time evolution in kspace
"""
function propagate_manual!(dpsi, psi, sim::Sim{1, Array{ComplexF64}}, t; info=false)
   @unpack ksquared, iswitch, dV, Vol,mu,gamma,dt = sim
   nlin_manual!(dpsi,psi,sim,t)
   @. psi = exp(dt/2 * (1.0 - im*gamma)*(-im*(1/2*ksquared - mu)))*psi 
   return nothing
end
# ==============

"""
Imaginary time evolution in xspace,
including explicit normalization
"""
function ground_state_nlin!(psi,sim::Sim{1, Array{ComplexF64}}, dt; info=false)
   @unpack ksquared,g,X,V0,iswitch,dV,Vol = sim; x = X[1]
   
   psi_i = copy(psi) 
   ground_state_evolve!(psi, sim, dt)
   mu = 0.0
   if iswitch == -im
      mu = chempot(psi, sim) # wainting for a more efficient implementation
   end
   @. psi += - dt/2 * (V0 + g*abs2(psi)) * psi + dt/2*mu * psi

   norm_diff = ns(psi - psi_i, sim)/dt
   psi .= psi / sqrt(ns(psi, sim))
   return norm_diff
end


"""
Imaginary time evolution in kspace
"""
function ground_state_evolve!(psi, sim::Sim{1, Array{ComplexF64}}, dt; info=false)
      @unpack ksquared,g,X,V0,iswitch,dV,Vol = sim; x = X[1]
      kspace!(psi, sim)
      @. psi += -dt/2*(1/2 *ksquared) * psi
      xspace!(psi, sim)
   return nothing
end


"""
Imaginary time evolution in xspace, 
using Crank Nicholson standard scheme
"""
function cn_ground_state!(psi,sim::Sim{1, Array{ComplexF64}}, dt, tri_fwd, tri_bkw; info=false)
   @unpack dt,g,X,V0,iswitch,dV,Vol = sim; x = X[1]
   psi_i = copy(psi) 
   nonlin = (dt/2) * g*abs2.(psi)
   tri_fwd += Diagonal(nonlin)
   tri_bkw += Diagonal(-nonlin)
   #tri_fwd *= 1/2
   #tri_bkw *= 1/2
   psi .= tri_fwd*psi
   psi .= transpose(\(psi, tri_bkw))

   norm_diff = ns(psi - psi_i, sim)/dt
   psi .= psi / sqrt(ns(psi, sim))
   return norm_diff
end


"""
Imaginary time evolution in xspace, 
using predictor-corrector scheme (i FWD Euler + 1 fix point iterate)
"""
function pc_ground_state!(psi,sim::Sim{1, Array{ComplexF64}}, dt, tri_fwd, tri_bkw; info=false)
   @unpack dt,g,X,V0,iswitch,dV,Vol,N = sim; x = X[1]
   psi_i = copy(psi) 
   nonlin = -(dt/2) * g*abs2.(psi)
   tri_fwd += - Diagonal(ones(N[1])) + Diagonal(nonlin)
   for i in 1:3
      mapslices(x -> \(x, tri_fwd[i]), psi, dims=(i))
   end
   psi_star = tri_fwd*psi + psi
   psi .= 1/2*(tri_fwd*psi) + psi

   nonlin_1 = -(dt/2) * g*abs2.(psi_star)
   tri_fwd .= Diagonal(nonlin_1-nonlin)
   psi .+= 1/2*(tri_fwd*psi_star) 
   tri_fwd = -  Diagonal(ones(N[1])) + Diagonal(nonlin)
   psi .= 1/2*(tri_fwd*psi_i + tri_fwd*psi) + psi
   @info display(sum(psi))

   norm_diff = ns(psi - psi_i, sim)/dt
   psi .= psi / sqrt(ns(psi, sim))
   return norm_diff
end


"""
Imaginary time evolution in xspace, 
using BKW Euler
"""
function be_ground_state!(psi,sim::Sim{1, Array{ComplexF64}}, dt, tri_fwd, tri_bkw; info=false)
   @unpack dt,g,X,V0,iswitch,dV,Vol,N = sim; x = X[1]
   psi_i = copy(psi) 
   nonlin = -(dt/2) * g*abs2.(psi)
   tri_bkw += Diagonal(nonlin)
   psi .= transpose(\(psi, tri_bkw))

   norm_diff = ns(psi - psi_i, sim)/dt
   psi .= psi / sqrt(ns(psi, sim))
   return norm_diff
end


"""
3D Imaginary time evolution in xspace, 
using BKW Euler
"""
function be_ground_state!(psi,sim::Sim{3, CuArray{ComplexF64}}, dt, tri_fwd, tri_bkw; info=false)
   @unpack dt,g,X,V0,iswitch,dV,Vol,N = sim; x = X[1]
   psi_i = copy(psi) 
   nonlin = -(dt/2) * g*abs2.(psi)
   tri_bkw += Diagonal(nonlin)
   psi .= transpose(\(psi, tri_bkw))

   norm_diff = ns(psi - psi_i, sim)/dt
   psi .= psi / sqrt(ns(psi, sim))
   return norm_diff
end


"""
Main solution routine
"""
function runsim(sim; info=false)
   @unpack psi_0, dV, dt, ti, tf, t, solver, iswitch, abstol, reltol, N,Nt, V0, maxiters, time_steps= sim
   info && @info ns(psi_0, sim)

   function savefunction(psi...)
      isdir(path) || mkpath(path)
      i = findfirst(x->x== psi[2],sim.t)
      padi = lpad(string(i),ndigits(length(sim.t)),"0")
      info && println("⭆ Save $i at t = $(trunc(ψ[2];digits=3))")
      # tofile = path*"/"*filename*padi*".jld2"
      tofile = joinpath(path,filename*padi*".jld2")
      save(tofile,"ψ",psi[1],"t",psi[2])
  end

  savecb = FunctionCallingCallback(savefunction;
                   funcat = sim.t, # times to save at
                   func_everystep=false,
                   func_start = true,
                   tdir=1)

   # due to normalization, ground state solution 
   # is computed with forward Euler
   boring = false
   if iswitch == -im 
      if boring == false
         sim.iswitch = 1.0
         if solver == SplitStep 

            ssalg = DynamicSS(BS3(); 
            reltol = sim.reltol,
            tspan = Inf)

            problem = ODEProblem(propagate!, psi_0, (ti, tf), sim)
            ss_problem = SteadyStateProblem(propagate!, psi_0, sim)

            sim.nfiles ?
            (sol = solve(ss_problem,
                        alg=ssalg,
                        callback=savecb,
                        dense=false,
                        maxiters=maxiters,
                        progress=true, 
                        #dt = 0.001
                        )) :
            (sol = solve(ss_problem,
                        alg=ssalg,
                        dense=false,
                        maxiters=maxiters,
                        progress=true, 
                        #dt = 0.001
                        ))
         elseif solver == CrankNicholson
            throw("Unimplemented")
         end
         return sol
      else
         xspace!(psi_0, sim)
         if solver == SplitStep 
            norm_diff = 1
            abstol_diff = abstol * dt
            #for i in  1:10000
            while norm_diff > abstol_diff
               norm_diff = ground_state_nlin!(psi_0,sim,dt)
               @info norm_diff
               # if norm_diff > abstol_diff * 1e5
               #    @warn "too fast"
               #    dt = dt * 0.9
               # end
            end
         else
            solvers = [ground_state_nlin!, cn_ground_state!, pc_ground_state!, be_ground_state!]
            func = solvers[solver.number]
            @info "Solving using solver" func 
            norm_diff = 1
            abstol_diff = abstol
            taglia = N[1]
            #for i in  1:10000
            d_central = -(dt/2) * ( 1/(dV^2) * ones(taglia) - V0) |> complex
            d_lu = (dt/2) * 1/(2*dV^2) * ones(taglia-1) |> complex
            tri_fwd = SymTridiagonal(d_central, d_lu) + Diagonal(ones(taglia)) # Dx
            tri_bkw = -SymTridiagonal(d_central, d_lu) + Diagonal(ones(taglia)) # Sx
            cnt = 0 
            while norm_diff > abstol_diff && cnt < maxiters
               norm_diff = func(psi_0,sim,dt, tri_fwd, tri_bkw)
               cnt +=1
            end
            @info "Computation ended after iterations" cnt
         end
         kspace!(psi_0, sim)
         sol = psi_0
         return [sol]
      end
   else # real-time dynamics
      if solver == SplitStep 
         problem = ODEProblem(propagate!, psi_0, (ti, tf), sim)
         try
         sim.nfiles ?
         (sol = solve(problem,
                     alg=Euler(),
                     reltol=sim.reltol,
                     saveat=sim.t[end],
                     dt=dt,
                     callback=savecb,
                     dense=false,
                     maxiters=maxiters,
                     progress=true)) :
         (sol = solve(problem,
                     alg=Euler(),
                     reltol=sim.reltol,
                     saveat=sim.t,
                     dt=dt,
                     dense=false,
                     maxiters=maxiters,
                     progress=true))
         catch err
            if isa(err, NpseCollapse)
               showerror(stdout, err)
            else
               throw(err)
            end
            return nothing
         end
      elseif solver == ManualSplitStep
         time = 0.0
         psi = 0.0 * psi_0
         psi .= psi_0
         dpsi = 0.0 * psi
         collection = Array{ComplexF64, 2}(undef, (length(psi_0), Nt))
         collection[:, 1] = psi

         save_interval = Int(round(time_steps/Nt))
         for i in 1:time_steps
            propagate_manual!(dpsi, psi, sim, time)
            if i % save_interval == 0
               collection[:, Int(floor(i / save_interval))] = psi
            end
            @info "norm" (nsk(psi_0, sim))
            time += dt
         end
         sol = CustomSolution(u=[collection[:, k] for k in 1:Nt], t=t)

      elseif solver != SplitStep
         throw("Unimplemented")
      end
   end
   return sol
end


function testsim(sim)
   err = false
   sol = try
           runsim(sim; info=false)
       catch e
           err = true
       end
return sol,err
end