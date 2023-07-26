JULIA_CUDA_SOFT_MEMORY_LIMIT = "95%"

function tiles(; use_precomputed_tiles=false)
  pyplot()
  if Threads.nthreads() == 1
    @warn "running in single thread mode!"
  else
    @info "running in multi-thread mode: n_threads =" Threads.nthreads()
  end

  save_path = "results/"
  gamma_list = [0.65]

  for gamma in gamma_list
    @info "==== Using gamma: " gamma
    sd = load_parameters_alt(gamma_param=gamma; eqs=["Np"], nosaves=true)
    @info "Required simulations: " keys(sd)
    prepare_for_collision!(sd, gamma)

    # check the extremes for stability
    if false
      @info "Computing the extremes..."
      check_eq = "G3"
      four_extremes = get_tiles(sd[check_eq], check_eq;
        tiles=2,
        plot_finals=true)
      print("--> Extremes computed. Going on? [N/y]")
      ans = readline()
      if ans != "y"
        return
      end
    end
    if isfile(save_path * "tile_dict.jld2")
      @info "Loading Tiles library..."
      tile_dict = JLD2.load(save_path * "tile_dict.jld2")
    else
      @info "No Tiles library found! Saving an empty one..."
      tile_dict = Dict()
      JLD2.save(save_path * "tile_dict.jld2", tile_dict)
    end

    for (name, sim) in sd
      @info "Tiling " name
      if haskey(tile_dict, hs(name, gamma)) && use_precomputed_tiles
        @info "Already found tile for " name, gamma
      else
        tile = get_tiles(sim, name; tiles=50)
        push!(tile_dict, hs(name, gamma) => tile)
        JLD2.save(save_path * "tile_dict.jld2", tile_dict)
      end
    end
  end
end

function get_tiles(
  sim::Sim{1,Array{Complex{Float64}}},
  name::String="noname";
  tiles=100,
  plot_finals=false)

  saveto = "../media/tiles_$(name).pdf"
  max_vel = 1
  max_bar = 1
  #
  vel_list = LinRange(0.1, max_vel, tiles)
  bar_list = LinRange(0, max_bar, tiles)
  tran = Array{Float64,2}(undef, (tiles, tiles))
  refl = Array{Float64,2}(undef, (tiles, tiles))

  @info "Filling sim grid..."
  sgrid = Array{Sim,2}(undef, (tiles, tiles))
  archetype = sim
  sgrid[1, 1] = archetype
  @time begin
    for (vx, vv) in enumerate(vel_list)
      for (bx, bb) in enumerate(bar_list)
        sgrid[bx, vx] = imprint_vel_set_bar(archetype; vv=vv, bb=bb)
      end
    end
  end
  # all sims have the same x
  mask_refl = map(xx -> xx > 0, sgrid[1, 1].X[1] |> real)
  mask_tran = map(xx -> xx < 0, sgrid[1, 1].X[1] |> real)

  @info "Running tiling..."
  avg_iteration_time = 0.0
  iter = Iterators.product(enumerate(vel_list), enumerate(bar_list))
  full_time = @elapsed for ((vx, vv), (bx, bb)) in ProgressBar(iter)
    sim = sgrid[bx, vx]
    collapse_occured = false
    @info "Computing tile" (vv, bb)
    sol = nothing
    try
      avg_iteration_time += @elapsed sol = runsim(sim; info=false)
      if plot_finals
        pp = plot_final_density(sol.u, sim; show=false)
        savefig(pp, "media/checks/final_$(name)_$(vv)_$(bb).pdf")
        qq = plot_axial_heatmap(sol.u, sim.t, sim; show=false)
        savefig(qq, "media/checks/heatmap_$(name)_$(vv)_$(bb).pdf")
      end
    catch err
      if isa(err, NpseCollapse) || isa(err, Gpe3DCollapse)
        collapse_occured = true
      else
        throw(err)
      end
    end


    # catch maxiters hit and set the transmission to zero
    if sim.manual == false
      if sol.retcode != ReturnCode.Success
        @info "Run complete, computing transmission..."
        @info "Detected solver failure"
        tran[bx, vx] = 0.0
        refl[bx, vx] = 1.0
        @info "T = " tran[bx, vx]
      else
        final = sol.u[end]
        @info "Run complete, computing transmission..."
        xspace!(final, sim)
        tran[bx, vx] = ns(final, sim, mask_tran)
        refl[bx, vx] = ns(final, sim, mask_refl)
        @info "T = " tran[bx, vx]
      end
    else
      if !collapse_occured
        final = sol.u[end]
        @info "Run complete, computing transmission..."
        xspace!(final, sim)
        tran[bx, vx] = ns(final, sim, mask_tran)
        refl[bx, vx] = ns(final, sim, mask_refl)
      else
        @info "Run complete, detected collapse..."
        tran[bx, vx] = NaN
      end
      @info "T = " tran[bx, vx]
    end
    if !isapprox(tran[bx, vx] + refl[bx, vx], 1.0, atol=1e-5)
      @warn "T+R != 1.0"
    end
  end
  @info "Tiling time            = " full_time
  @info "Total time in solver   = " avg_iteration_time
  @info "Average iteration time = " avg_iteration_time / tiles^2

  JLD2.@save("tran_$(name).jld2", tran)
  JLD2.@save("refl_$(name).jld2", refl)
  norm_bar = bar_list / max_bar
  norm_vel = vel_list / max_vel
  return tran
end

"""
in the 3D case we do not have sufficient GPU mem, so we go serially
"""
function get_tiles(
  archetype::Sim{3,CuArray{Complex{Float64}}},
  name::String="noname";
  tiles=100,
  plot_finals=false)

  saveto = "../media/tiles_$(name).pdf"
  max_vel = 1
  max_bar = 1
  #
  vel_list = LinRange(0.1, max_vel, tiles)
  bar_list = LinRange(0, max_bar, tiles)
  tran = Array{Float64,2}(undef, (tiles, tiles))
  refl = Array{Float64,2}(undef, (tiles, tiles))

  @info "Proceeding serially from the archetype..."
  # all sims have the same x
  mask_refl = map(xx -> xx > 0, archetype.X[1] |> real)
  mask_tran = map(xx -> xx < 0, archetype.X[1] |> real)

  @info "Running tiling..."
  avg_iteration_time = 0.0
  iter = Iterators.product(enumerate(vel_list), enumerate(bar_list))
  full_time = @elapsed for ((vx, vv), (bx, bb)) in ProgressBar(iter)
    sim = deepcopy(archetype)
    collapse_occured = false
    imprint_vel_set_bar!(sim; vv=vv, bb=bb)
    @info "Computing tile" (vv, bb)
    sol = nothing
    try
      avg_iteration_time += @elapsed sol = runsim(sim; info=false)
      if plot_finals
        pp = plot_final_density(sol.u, sim; show=false)
        savefig(pp, "media/checks/final_$(name)_$(vv)_$(bb).pdf")
        qq = plot_axial_heatmap(sol.u, sim.t, sim; show=false)
        savefig(qq, "media/checks/heatmap_$(name)_$(vv)_$(bb).pdf")
      end


    catch err
      if isa(err, NpseCollapse) || isa(err, Gpe3DCollapse)
        collapse_occured = true
      else
        throw(err)
      end
    end


    # catch maxiters hit and set the transmission to zero
    if sim.manual == false
      if sol.retcode != ReturnCode.Success
        @info "Run complete, computing transmission..."
        @info "Detected solver failure"
        tran[bx, vx] = 0.0
        refl[bx, vx] = 1.0
        @info "T = " tran[bx, vx]
      else
        if !collapse_occured
          final = sol.u[end]
          @info "Run complete, computing transmission..."
          xspace!(final, sim)
          tran[bx, vx] = ns(final, sim, mask_tran)
          refl[bx, vx] = ns(final, sim, mask_refl)
        else
          @info "Run complete, detected collapse..."
          tran[bx, vx] = NaN
        end
        @info "T = " tran[bx, vx]
      end
    else
      if !collapse_occured
        final = sol.u[end]
        @info "Run complete, computing transmission..."
        xspace!(final, sim)
        tran[bx, vx] = ns(final, sim, mask_tran)
        refl[bx, vx] = ns(final, sim, mask_refl)
      else
        @info "Run complete, detected collapse..."
        tran[bx, vx] = NaN
        refl[bx, vx] = NaN
      end
      @info "T = " tran[bx, vx]
    end
    if !isapprox(tran[bx, vx] + refl[bx, vx], 1.0, atol=1e-5)
      @warn "T+R != 1.0"
    end
  end
  @info "Tiling time            = " full_time
  @info "Total time in solver   = " avg_iteration_time
  @info "Average iteration time = " avg_iteration_time / tiles^2

  JLD2.@save("tran_$(name).jld2", tran)
  JLD2.@save("refl_$(name).jld2", refl)
  norm_bar = bar_list / max_bar
  norm_vel = vel_list / max_vel
  return tran
  return tran
end

function view_all_tiles()
  tile_file = "results/tile_dict.jld2"
  @assert isfile(tile_file)
  td = load(tile_file)
  for (k, v) in td
    @info "found" ihs(k)
    baxis = LinRange(0.0, 1.0, size(v)[1])
    vaxis = LinRange(0.1, 1.0, size(v)[1])
    ht2 = heatmap(vaxis, baxis, v, clabels=true, xlabel="v", ylabel="b")
    savefig(ht2, "media/tiles_" * string(ihs(k)) * "_ht.pdf")
    v, mask = process_tiles(v)
    ht = contour(vaxis, baxis, v, clabels=true, xlabel="v", ylabel="b")
    contour!(ht, vaxis, baxis, mask,  levels = [0.0], color=:turbo, linestyle=:dot ,linewidth=1.8)
    savefig(ht, "media/tiles_" * string(ihs(k)) * "_ct.pdf")
  end
end

function process_tiles(tt)
  mask = ones(size(tt))
  # FIXME the names
  for bar in 1:size(tt)[1]
    for vel in 2:size(tt)[2]
      if abs(tt[vel, bar] - tt[vel-1, bar]) > 0.3
        tt[vel, bar] = NaN
        for velx in 1:vel
          mask[velx, bar] = 0.0
        end
      end
    end
  end

  flag_prev = true
  flag_curr = true
  posv = 1
  posb = 1
  for vel in 1:size(tt)[2]
    flag_curr = true
    for bar in 1:size(tt)[1]
      if mask[vel, bar] == 0.0
        flag_curr = false
        posv = vel
        posb = bar
      end
    end
    if flag_prev == false && flag_curr == true
      for velx in 1:posv
        mask[velx, posb] = NaN
      end
      return tt, mask
    end
    flag_prev = flag_curr
  end
  return tt, mask
end