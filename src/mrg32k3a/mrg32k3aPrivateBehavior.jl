#
# Implementation of MRG32k3a RNG Streams
#
########################################
module PrivateMRGFuncs
const m1 = Int64(2^32 - 209)
const m2 = Int64(2^32 - 22853)
const a12 = Int64(1403580)
const a13 = Int64(-810728)
const a21 = Int64(527612)
const a23 = Int64(-1370589)
const norm = Float64(1.0 / (1 + m1))
const two17 = Int64(131072)
const two53 = Int64(9007199254740992)

const DEFAULT_SEED = [ 12345, 12345, 12345, 12345, 12345, 12345 ]

const A1p0 =  [  0     1     0   ;
                 0     0     1   ;
                 a13   a12   0   ]

const A2p0 =  [  0     1     0   ;
                 0     0     1   ;
                 a23   0     a21 ]

const A1p76 =  [   82758667  1871391091  4127413238 ;
                 3672831523    69195019  1871391091 ;
                 3672091415  3528743235    69195019 ]

const A2p76 =  [ 1511326704  3759209742  1610795712 ;
                 4292754251  1511326704  3889917532 ;
                 3859662829  4292754251  3708466080 ]

const A1p127 = [ 2427906178  3580155704   949770784 ;
                  226153695  1230515664  3580155704 ;
                 1988835001   986791581  1230515664 ]

const A2p127 = [ 1464411153   277697599  1610723613 ;
                   32183930  1464411153  1022607788 ;
                 2824425944    32183930  2093834863 ]

const InvA1  = [  184888585           0  1945170933 ;
                          1           0           0 ;
                          0           1           0 ]

const InvA2 =  [          0   360363334  4225571728 ;
                          1           0           0 ;
                          0           1           0 ]
"""
Ensures a given seed is valid for MRG32k3a random number generator.
"""
function checkseed(x::Vector{Int})
    return length(x) == 6     &&
            all(x[1:6] .>= 0)  &&
            all(x[1:3] .< m1)  &&
            all(x[4:6] .< m2)  &&
        ~all(x[1:3] .== 0)   &&
        ~all(x[4:6] .== 0)
end

"""
Computes (a*s + c) % m, all must be < 2^35. Overflow-safe.
"""
function MultModM(a::Int64, s::Int64, c::Int64, m::Int64)
    val = a * Float64(s) + c
    if abs(val) < two53
        v = Int64(val)
    else
        a1 = a ÷ two17
        a -= a1 * two17
        v  = (a1 * s) % m
        v  = v * two17 + a * s + c
    end
    v %= m
    v += (v < 0) ? m : 0
    return v
end

"""
Computes A*s % m, assuming abs(s[i]) < m. Overflow-safe.
"""
function MatVecModM(A::Array{Int64,2},s::Array{Int64,1}, m::Int64)

    v = [0,0,0]
    for i = 1:3
        for j = 1:3
            v[i] = MultModM(A[i,j], s[j], v[i], m)
        end
    end

    return v
end

"""
Computes matrix A*B % m, assuming abs(s[i]) < m. Overflow-safe.
"""
function MatMatModM(A::Array{Int64,2}, B::Array{Int64,2}, m::Int64)

    C = diagm([0,0,0])
    for i = 1:3
        C[:,i] = MatVecModM(A,B[:,i],m)
    end

    return C
end

"""
Computes the matrix A^(2^e) % m. Overflow-safe.
"""
function MatTwoPowModM(A::Array{Int64,2}, e::Int64, m::Int64)

    B = A
    for i = 1:e
        B = MatMatModM(B, B, m)
    end

    return B
end

"""
Computes the matrix  (A^n % m). Overflow-safe.
"""
function MatPowModM(A::Array{Int64,2}, n::Int64, m::Int64)
    W = A
    B = diagm([1,1,1])

    while n > 0
        if ( n % 2 == 1 )
            B = MatMatModM(W, B, m)
        end
        W = MatMatModM(W, W, m)
        n ÷= 2
    end
    return B
end
end
const PMF = PrivateMRGFuncs