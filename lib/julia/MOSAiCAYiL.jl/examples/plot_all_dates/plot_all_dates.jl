#=

    Plot the ERA5 testbed forcing and the LES final state for AYiL dates.

        julia> include("examples/plot_all_dates/plot_all_dates.jl"); plot_catalog();
        julia> include("examples/plot_all_dates/plot_all_dates.jl"); plot_catalog(dates = ["20200503", "20191025"])

    Full-height plots go in figures/full_height/; inset plots zoomed to the cloud
    region go in figures/inset/. Each is written as `*.png` and `*.pdf`.

    Dates in the `best` set (those without challenging ice initializations) have
    green axis borders and a horizontal dashed line at that day's `best_z_max`
    (`RAW_BEST_SIMULATION_TOP_C`).

=#

using MOSAiCAYiL: MOSAiCAYiL as MA
using CairoMakie: CairoMakie as CM

const figures_dir = joinpath(@__DIR__, "figures")

const NCOLS = 3
const CONDENSATE_MIN = 1.0e-8
const INSET_PAD = 1.3
const INSET_Z_FLOOR = 800.0
const BEST_SPINE = :seagreen
const ZMAX_LINE = :black

"""Archive name of one SB3 scalar, from `MA.SB3_SCALAR_INDEX`."""
sb3_raw(species::Symbol) = "sv" * lpad(string(getfield(MA.SB3_SCALAR_INDEX, species)), 3, '0')

"""LES slab-mean column at the last profile time: `MA.dales_slab_column` plus SB3 masses."""
function load_les_final(date)
    return MA.open_archive(:profiles, date) do ds
        col = MA.dales_slab_column(ds)
        t = lastindex(col.time)
        mass(species) =
            MA.read_variable(ds, sb3_raw(species); file = :profiles).data[:, t]
        return (;
            z = col.z,
            thl = col.θ_l[:, t],
            T = col.T[:, t],
            qt = col.q_tot[:, t],
            u = col.u[:, t],
            v = col.v[:, t],
            ql = col.q_liq[:, t],
            qi = mass(:q_cloud_ice),
            qr = mass(:q_rain),
            qs = mass(:q_snow),
            qg = mass(:q_graupel),
        )
    end
end

"""
Testbed forcing on the LES centres.

`θ_l` is `MA.liquid_pottemp` from interpolated `T`, `p`, `q_l` — the archive's
`thl`. `q_t` is `q + q_l`, matching DALES `qt` (not `hus`, which also includes ice).
Rain, snow and graupel are not in `scm_in`.
"""
function load_forcing(z, date)
    f = MA.interpolate_forcing(MA.testbed_forcing(date), z)
    b = MA.DefaultThermodynamicsBackend()
    θ_l = MA.liquid_pottemp.(Ref(b), f.ta, f.p, f.ql)
    return (;
        thl = θ_l,
        T = f.ta,
        qt = f.q .+ f.ql,
        u = f.ua,
        v = f.va,
        ql = f.ql,
        qi = f.qi,
    )
end

"""
Panels in figure order (3×3): θ_l, T, u/v (v dashed); q_t, q_l, q_i; q_r, q_s, q_g.

A winds panel carries `(u, v)` in `forcing` and `les`.
"""
function day_panels(forcing, les)
    return (
        (; xlabel = "θ_l [K]", forcing = forcing.thl, les = les.thl),
        (; xlabel = "T [K]", forcing = forcing.T, les = les.T),
        (; xlabel = "u, v [m/s]", forcing = (forcing.u, forcing.v), les = (les.u, les.v), winds = true),
        (; xlabel = "q_t [kg/kg]", forcing = forcing.qt, les = les.qt),
        (; xlabel = "q_l [kg/kg]", forcing = forcing.ql, les = les.ql),
        (; xlabel = "q_i [kg/kg]", forcing = forcing.qi, les = les.qi),
        (; xlabel = "q_r [kg/kg]", forcing = nothing, les = les.qr),
        (; xlabel = "q_s [kg/kg]", forcing = nothing, les = les.qs),
        (; xlabel = "q_g [kg/kg]", forcing = nothing, les = les.qg),
    )
end

"""Highest cloudy `z` in the plotted LES condensate, with pad; inversion fallback."""
function inset_ymax(date, z, les)
    cloudy =
        (les.ql .> CONDENSATE_MIN) .|
        (les.qi .> CONDENSATE_MIN) .|
        (les.qr .> CONDENSATE_MIN) .|
        (les.qs .> CONDENSATE_MIN) .|
        (les.qg .> CONDENSATE_MIN)
    z_cloud = any(cloudy) ? maximum(z[cloudy]) : 1.5 * MA.inversion_height(date)
    return clamp(INSET_PAD * z_cloud, INSET_Z_FLOOR, last(z))
end

function style_best!(ax, z_max; label = false)
    ax.bottomspinecolor = BEST_SPINE
    ax.topspinecolor = BEST_SPINE
    ax.leftspinecolor = BEST_SPINE
    ax.rightspinecolor = BEST_SPINE
    ax.spinewidth = 2.5
    # black, not seagreen: a green dash on a green spine disappears at the column top
    CM.hlines!(
        ax, z_max;
        color = ZMAX_LINE, linestyle = :dash, linewidth = 2,
        label = label ? "best z_max" : nothing,
    )
    return ax
end

"""x-limits from samples whose `z` sits in `ylim`, so an inset is not autoscaled by the column top."""
function restrict_xlim!(ax, z, ylim, series; from_zero::Bool)
    y0, y1 = ylim
    vals = Float64[]
    for x in series
        isnothing(x) && continue
        for i in eachindex(z)
            y0 <= z[i] <= y1 && push!(vals, Float64(x[i]))
        end
    end
    isempty(vals) && return ax
    lo, hi = extrema(vals)
    if from_zero
        lo = zero(lo)
        hi = max(hi, 10 * CONDENSATE_MIN)
    elseif hi ≈ lo
        lo -= 1
        hi += 1
    end
    pad = 0.05 * (hi - lo)
    CM.xlims!(ax, lo - (from_zero ? 0 : pad), hi + pad)
    return ax
end

function full_ylim(z, z_max)
    top = Float64(last(z))
    isnothing(z_max) && return (0.0, top)
    return (0.0, max(top, Float64(z_max)) * 1.08)
end

"""Cloud-region ylim; widened to include `z_max` unless that cap is the column top."""
function inset_ylim(date, z, les, z_max)
    y = inset_ymax(date, z, les)
    top = last(z)
    if !isnothing(z_max) && z_max < 0.9 * top
        y = max(y, (z_max) * 1.15)
    end
    return (0.0, min(y, top * 1.08))
end

function plot_day(z, panels; title, ylim, z_max)
    n = length(panels)
    fig = CM.Figure(size = (380 * NCOLS, 320 * cld(n, NCOLS) + 50))
    axes = CM.Axis[]
    for (i, p) in enumerate(panels)
        row, col = fldmod1(i, NCOLS)
        ax = CM.Axis(
            fig[row, col];
            xlabel = p.xlabel,
            ylabel = col == 1 ? "z [m]" : "",
        )
        push!(axes, ax)
        winds = get(p, :winds, false)
        if winds
            fu, fv = p.forcing
            lu, lv = p.les
            CM.lines!(ax, fu, z; color = :black, linewidth = 2)
            CM.lines!(ax, fv, z; color = :black, linewidth = 2, linestyle = :dash)
            CM.lines!(ax, lu, z; color = :steelblue, linewidth = 2, label = "u")
            CM.lines!(ax, lv, z; color = :steelblue, linewidth = 2, linestyle = :dash, label = "v")
            series = (fu, fv, lu, lv)
        else
            isnothing(p.forcing) ||
                CM.lines!(ax, p.forcing, z; color = :black, linewidth = 2, label = "forcing")
            CM.lines!(ax, p.les, z; color = :steelblue, linewidth = 2, label = "LES final")
            series = (p.forcing, p.les)
        end
        isnothing(z_max) || style_best!(ax, z_max; label = i == 1)
        restrict_xlim!(ax, z, ylim, series; from_zero = startswith(p.xlabel, "q"))
        if i == 1 || winds
            CM.axislegend(ax; position = :lt, framevisible = false)
        end
    end
    CM.linkyaxes!(axes...)
    for ax in axes
        CM.ylims!(ax, ylim)
    end
    CM.Label(fig[0, :], title; fontsize = 16)
    return fig
end

function save_figure(fig, dir, key)
    mkpath(dir)
    for ext in ("png", "pdf")
        CM.save(joinpath(dir, "$(key).$(ext)"), fig; px_per_unit = 2)
    end
    return nothing
end

"""
    plot_catalog(dates)

Write full-height and inset figures for each date. `dates` may be `Date`s, `yyyymmdd`
strings, or the catalog tuple.
"""
function plot_catalog(dates = collect(MA.MOSAiCAYiL_dates))
    ld = length(dates)
    MA.data_available() || error(
        "The AYiL archive is not installed; plot_all_dates needs scm_in and profiles.",
    )
    best = Set(MA.best_dates())
    full_dir = joinpath(figures_dir, "full_height")
    inset_dir = joinpath(figures_dir, "inset")
    mkpath(full_dir)
    mkpath(inset_dir)
    for (i, date) in enumerate(dates)
        key = MA.date_string(date)
        les = load_les_final(date)
        forcing = load_forcing(les.z, date)
        panels = day_panels(forcing, les)
        z_max = key in best ? MA.RAW_BEST_SIMULATION_TOP_C[key] : nothing
        title = key
        save_figure(
            plot_day(les.z, panels; title, ylim = full_ylim(les.z, z_max), z_max),
            full_dir,
            key,
        )
        save_figure(
            plot_day(
                les.z, panels;
                title,
                ylim = inset_ylim(date, les.z, les, z_max),
                z_max,
            ),
            inset_dir,
            key,
        )
        @info "wrote $(date) | $(i) / $(ld)"
    end
    return nothing
end


