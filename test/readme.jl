# Runs every ```julia code block from the README in an isolated module so that
# the examples cannot silently rot when the package evolves.
@testset "README examples" begin
    readme_path = joinpath(dirname(@__DIR__), "README.md")
    text = read(readme_path, String)
    blocks = [strip(replace(m.captures[1], '\r' => ""))
              for m in eachmatch(r"```julia\r?\n(.*?)```"s, text)]
    @test length(blocks) >= 5

    for (i, code) in enumerate(blocks)
        # installation snippets shell out to Pkg; they are not executable here
        occursin("Pkg.", code) && continue
        title = first(split(code, '\n'))
        @testset "README block $i: $title" begin
            mod = Module(gensym(:ReadmeExample))
            Core.eval(mod, :(using RandomDataStreams, Random))
            ok = try
                Core.eval(mod, Meta.parseall(code))
                true
            catch err
                println(stderr, sprint(showerror, err))
                false
            end
            @test ok
        end
    end
end
