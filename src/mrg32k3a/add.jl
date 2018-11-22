function copy(m::MRG32k3a)
    MRG32k3a(copy(m.Cg), copy(m.Bg), copy(m.Ig))
end