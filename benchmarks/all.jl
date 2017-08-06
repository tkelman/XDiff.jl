
# using XDiff
# using Espresso: @get_or_create
import Espresso
import XDiff
for n in Base.names(Espresso, true) @eval import Espresso: $n end
for n in Base.names(XDiff, true) @eval import XDiff: $n end


using ReverseDiff: GradientTape, GradientConfig, gradient, gradient!, compile
using BenchmarkTools

include("functions.jl")


function load_espresso()
    # TODO: remove
    for n in Base.names(Espresso, true) @eval import Espresso: $n end
    for n in Base.names(XDiff, true) @eval import XDiff: $n end
end



function perf_test(f; compile_tape=true, inputs...)
    vals = ([val for (name, val) in inputs]...)
    println("Compiling derivatives using XDiff")
    @time df = xdiff(f; inputs...)
    mem = Dict()
    println("Testing XDiff...")
    r1 = @benchmark $df($vals...; mem=$mem)
    show(STDOUT, MIME{Symbol("text/plain")}(), r1)
    println("\n")

    f_tape = GradientTape(f, vals)
    if compile_tape
        compiled_f_tape = compile(f_tape)
    end
    cfg = GradientConfig(vals)
    results = map(similar, vals)
    println("Testing ReverseDiff...")
    if compile_tape
        r2 = @benchmark gradient!($results, $compiled_f_tape, $vals)
    else
        r2 = @benchmark gradient!($results, $f_tape, $vals)
    end
    show(STDOUT, MIME{Symbol("text/plain")}(), r2)
    println("\n----------------------------------------\n")
    return r1, r2
end




function benchmark_autoencoder()
    f = autoencoder_cost
    println("\n## On larger data\n")
    We1 = rand(2000, 10_000); b1 = rand(2000); We2 = rand(1000, 2000); b2 = rand(1000);
    Wd = rand(10_000, 1000); x = rand(10_000, 100);
    inputs = [:We1 => We1, :We2 => We2, :Wd => Wd, :b1 => b1, :b2 => b2, :x => x];
    perf_test(f; inputs...)

    println("\n## On smaller data\n")
    We1 = rand(200, 1000); b1 = rand(200); We2 = rand(100, 200); b2 = rand(100);
    Wd = rand(1000, 100); x = rand(1000, 100);
    inputs = [:We1 => We1, :We2 => We2, :Wd => Wd, :b1 => b1, :b2 => b2, :x => x];
    perf_test(f; compile_tape=false, inputs...)
end


function benchmark_mlp1()
    f = mlp1
    w1=rand(2000, 10000); w2=rand(1000, 2000); w3=rand(1000, 1000); x1=rand(10000, 500);
    inputs = [:w1=>w1, :w2=>w2, :w3=>w3, :x1=>x1];
    perf_test(f; inputs...)

    w1=rand(200, 1000); w2=rand(100, 200); w3=rand(100, 100); x1=rand(1000, 10);
    inputs = [:w1=>w1, :w2=>w2, :w3=>w3, :x1=>x1];
    perf_test(f; inputs...)
end


function benchmark_mlp2()
    f = mlp2
    w1 = randn(2000, 10000); w2 = randn(1000, 2000); w3 = randn(1000, 1000); x1 = randn(10000, 500);
    b1 =  randn(2000); b2 = randn(1000); b3 = randn(1000)
    inputs = [:w1=>w1, :w2=>w2, :w3=>w3, :b1 => b1, :b2 => b2, :b3 => b3, :x1=>x1];
    perf_test(f; inputs...)

    w1=rand(200, 1000); w2=rand(100, 200); w3=rand(100, 100); x1=rand(1000, 10);
    b1 =  rand(200); b2 = rand(100); b3 = rand(100)
    inputs = [:w1=>w1, :w2=>w2, :w3=>w3, :b1 => b1, :b2 => b2, :b3 => b3, :x1=>x1];
    perf_test(f; inputs...)
end


function benchmark_rnn()
    f = rnn
    Wxh = randn(4096, 4096); Whh = randn(4096, 4096); Why = randn(128, 4096);
    hprev = randn(4096); x = randn(4096); y = randn(128);    
    inputs = [:Wxh=>Wxh, :Whh=>Whh, :Why=>Why, :hprev => hprev, :x => x, :y=>y];
    perf_test(f; inputs...)

    w1=rand(200, 1000); w2=rand(100, 200); w3=rand(100, 100); x1=rand(1000, 10);
    b1 =  rand(200); b2 = rand(100); b3 = rand(100)
    inputs = [:w1=>w1, :w2=>w2, :w3=>w3, :b1 => b1, :b2 => b2, :b3 => b3, :x1=>x1];
    perf_test(f; inputs...)
end
