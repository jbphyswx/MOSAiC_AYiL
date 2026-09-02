using NCDatasets: NCDatasets as NC

"""
    write_fielddump_tiles(dir; nx, ny_per_tile, n_tiles, nz, nt, expnr)

A y-decomposed set of `fielddump.III.JJJ.NNN.nc` tiles under `dir`, as DALES writes them,
returning the global field of each variable.

Values are distinct at every global point, so a stitch that misplaces a tile cannot agree
with the expected field. `u`, `v` and `w` sit on `xm`, `ym` and `zm`.
"""
function write_fielddump_tiles(
    dir::AbstractString;
    nx::Int = 8,
    ny_per_tile::Int = 4,
    n_tiles::Int = 2,
    nz::Int = 3,
    nt::Int = 2,
    expnr::AbstractString = "001",
)
    ny = ny_per_tile * n_tiles
    point(v, i, j, k, t) = Float32(v * 1.0f6 + i * 1.0f4 + j * 1.0f2 + k * 1.0f0 + t * 0.1f0)
    layout = (
        ("thl", ("xt", "yt", "zt", "time"), "K", 1),
        ("v", ("xt", "ym", "zt", "time"), "m/s", 2),
        ("w", ("xt", "yt", "zm", "time"), "m/s", 3),
        ("sv001", ("xt", "yt", "zt", "time"), "(kg/kg)", 4),
    )
    expected = Dict(
        name => [point(v, i, j, k, t) for i in 1:nx, j in 1:ny, k in 1:nz, t in 1:nt]
        for (name, _, _, v) in layout
    )

    for tile in 0:(n_tiles - 1)
        js = (tile * ny_per_tile + 1):((tile + 1) * ny_per_tile)
        path = joinpath(dir, "fielddump.000.$(lpad(tile, 3, '0')).$expnr.nc")
        NC.NCDataset(path, "c") do ds
            NC.defDim(ds, "xt", nx)
            NC.defDim(ds, "xm", nx)
            NC.defDim(ds, "yt", ny_per_tile)
            NC.defDim(ds, "ym", ny_per_tile)
            NC.defDim(ds, "zt", nz)
            NC.defDim(ds, "zm", nz)
            NC.defDim(ds, "time", nt)
            for (axis, values) in (
                ("xt", Float64.(1:nx) .* 20 .- 10), ("xm", Float64.(1:nx) .* 20 .- 20),
                ("yt", Float64.(js) .* 20 .- 10), ("ym", Float64.(js) .* 20 .- 20),
                ("zt", Float64.(1:nz) .* 10 .- 5), ("zm", Float64.(1:nz) .* 10 .- 10),
                ("time", Float64.(1:nt) .* 1800),
            )
                NC.defVar(ds, axis, collect(values), (axis,))
            end
            for (name, dims, units, v) in layout
                a = [point(v, i, j, k, t) for i in 1:nx, j in js, k in 1:nz, t in 1:nt]
                NC.defVar(ds, name, a, dims; attrib = ["units" => units])
            end
        end
    end
    return (; expected, nx, ny, nz, nt, n_tiles)
end
