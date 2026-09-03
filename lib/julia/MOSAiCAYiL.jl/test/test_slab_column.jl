using MOSAiCAYiL: MOSAiCAYiL as MA
using Test: Test

Test.@testset "dales_slab_column" begin
    b = MA.DefaultThermodynamicsBackend()
    date = "20200503"
    c = MA.dales_slab_column(date, Float64)
    cdef = MA.dales_slab_column(date)

    Test.@test eltype(cdef.presf) === Float32          # the archive's own type
    Test.@test eltype(c.presf) === Float64
    Test.@test length(c.z) == 286
    Test.@test size(c.presf) == (length(c.z), length(c.time))
    Test.@test size(c.T) == size(c.presf)
    Test.@test c.ps == c.presh[1, :]

    raw(v) = Float64.(
        MA.read_variable(v, date; file = :profiles, translate_units = false).data
    )
    presh_file, rhof_file = raw("presh"), raw("rhof")

    # `presh` and `rhof` are read, never reconstructed
    Test.@test c.presh == presh_file
    Test.@test c.rhof == rhof_file

    # so the reconstruction is what carries a claim about the routine
    for k in axes(presh_file, 2)
        rebuilt = MA.pressure_fromztop(
            c.ps[k], c.θ[:, k], c.q_tot[:, k], c.q_liq[:, k], c.z; backend = b,
        ).presh
        Test.@test maximum(abs, (rebuilt .- presh_file[:, k]) ./ presh_file[:, k]) < 1.0e-5
    end

    # `presf` is the full-level pressure, a different quantity the archive does not carry
    Test.@test maximum(abs, (c.presf .- presh_file) ./ presh_file) > 1.0e-2

    # the column closes on itself: rho from (presf, theta_v, exner) is the stored rhof
    ρ_recomputed = c.presf ./ (MA.R_d(b) .* c.θ_v .* c.exner)
    Test.@test maximum(abs, (ρ_recomputed .- rhof_file) ./ rhof_file) < 1.0e-3

    # theta_l and q_tot round-trip through the temperature the column reports
    Test.@test c.T ≈ MA.exner.(b, c.presf) .* c.θ_l .+
                     (MA.L_v0(b) / MA.cp_d(b)) .* c.q_liq

    # les_density is one column of it, at the archive's precision
    z, ρ = MA.les_density(date)
    Test.@test z == cdef.z
    Test.@test ρ == cdef.rhof[:, 1]
    Test.@test eltype(ρ) === Float32
end
