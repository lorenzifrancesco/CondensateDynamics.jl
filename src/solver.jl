
include("solvers_1D_auto.jl")
include("solvers_1D_manual.jl")
include("solvers_3D_auto.jl")
include("solvers_3D_manual.jl")

function manual_run(sim; info=false)
   @unpack psi_0, dV, dt, ti, tf, t, solver, iswitch, abstol, reltol, N,Nt, V0, maxiters, time_steps = sim
   info && @info "Running on manual mode: time_steps =  " time_steps
   if iswitch == -im # select solver and run manual convergence routine 
      if solver == SplitStep
         #xspace!(psi_0, sim)
         norm_diff = 1
         abstol_diff = abstol
         cnt = 0 
         info && print("\n")
         while norm_diff > abstol_diff && cnt < maxiters
            try
               norm_diff = ground_state_evolve!(psi_0,sim,dt; info=info)
               info && print("\r Interation number: ", cnt, " - norm diff: ", norm_diff)
            catch err
               if isa(err, NpseCollapse)
                  showerror(stdout, err)
               else
                  throw(err)
               end
            return nothing
            end
            cnt +=1
         end
         info && @info "Computation ended after iterations" cnt
         #kspace!(psi_0, sim)
         sol = CustomSolution(u=psi_0, t=t)
         info && @info sol
      else # nonspectral methods
         xspace!(psi_0, sim)
         solvers = [ground_state_nlin!, cn_ground_state!, pc_ground_state!, be_ground_state!]
         func = solvers[solver.number]
         info && @info "Solving using solver" func 
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
         info && @info "Computation ended after iterations" cnt
         kspace!(psi_0, sim)
         sol = CustomSolution(u=psi_0, t=t)
      end
      return sol
   else
      # in manual run mode the number of steps is specified by time_steps
      
      time = 0.0
      if length(N) == 1
         collection = Array{ComplexF64, 2}(undef, (length(psi_0), Nt))
         collection[:, 1] = psi_0
         save_counter = 1
         solve_time_axis = LinRange(ti, tf, time_steps)
         for i in 1:time_steps
            try
               propagate_manual!(psi_0, sim, time)
            catch err
               if isa(err, NpseCollapse)
                  showerror(stdout, err)
               else
                  throw(err)
               end
            return nothing
            end
            if t[save_counter] < solve_time_axis[i]
               collection[:, save_counter] = psi_0
               save_counter += 1
            end
            time += dt
         end
         sol = CustomSolution(u=[collection[:, k] for k in 1:Nt], t=t)
         info && @info sol
      elseif length(N) == 3
         collection = CuArray{ComplexF64, 4}(undef, (N..., Nt))
         collection[:, :, :, 1] = psi_0
         save_interval = Int(round(time_steps/Nt))
         for i in 1:time_steps
            try
               propagate_manual!(psi_0, sim, time)
            catch err
               if isa(err, NpseCollapse)
                  showerror(stdout, err)
               else
                  throw(err)
               end
            return nothing
            end
            if i % save_interval == 0
               collection[:, :, :, Int(floor(i / save_interval))] = psi_0
            end
            time += dt
         end
         sol = CustomSolution(u=[collection[:,:,:, k] for k in 1:Nt], t=t)
      end
      return sol
   end
end

function auto_run(sim; info=false)
   @unpack psi_0, dV, dt, ti, tf, t, solver, iswitch, abstol, reltol, N,Nt, V0, maxiters, time_steps = sim
   @assert solver == SplitStep
   if iswitch == -im # solve a steady state problem
      #sim.iswitch = 1.0 # we should catch NPSE collapse in ground state?
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
   else # propagate in real time
      problem = ODEProblem(propagate!, psi_0, (ti, tf), sim)
      try
      sim.nfiles ?
      (sol = solve(problem,
                  alg=sim.alg,
                  reltol=sim.reltol,
                  saveat=sim.t[end],
                  dt=dt,
                  callback=savecb,
                  dense=false,
                  maxiters=maxiters,
                  progress=true)) :
      (sol = solve(problem,
                  alg=sim.alg,
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
   end
   return sol
end

"""
Main solution routine
"""
function runsim(sim; info=false)
   @unpack psi_0, dV, dt, ti, tf, t, solver, iswitch, abstol, reltol, N,Nt, V0, maxiters, time_steps, manual = sim
   
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

   info && @info ns(psi_0, sim)
   if manual == true
      sol = manual_run(sim; info)
   else 
      sol = auto_run(sim; info)
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