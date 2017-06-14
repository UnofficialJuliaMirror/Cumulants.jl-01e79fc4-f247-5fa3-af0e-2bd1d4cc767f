#!/usr/bin/env julia

using Cumulants
using PyCall
@pyimport matplotlib as mpl
mpl.use("Agg")
using PyPlot
mpl.rc("text", usetex=true)
mpl.rc("font", family="serif", size = 12)
using ProfileView
using JLD, HDF5

function comptime(data::Matrix{Float64}, ccalc::Function, m::Int, b::Int)
  ccalc(data[1:4, 1:4], m, b)
  t = time_ns()
  # Profile.clear()
  ccalc(data, m, b)
  # ProfileView.view()
  # readline()
  Float64(time_ns()-t)/1.0e9
end


function comptimesonprocs(t::Int, n::Int, m::Int, p::Int = 12)
  data = randn(t, n)
  times = zeros(p)
  for i in 1:p
    addprocs(i)
    @everywhere using Cumulants
    println(i)
    times[i]=comptime(data, moment, m, 3)
    rmprocs(workers())
  end
  times
end



function plot(t::Int, n::Int, m::Int)
  times = comptimesonprocs(t,n,m)
  b = times[1]./times[1:end]
  fig, ax = subplots(figsize = (4.6, 4.6))
  ax[:plot](collect(1:length(b)), b, "--x", label= "m = $m, t = $t, n = $n")
  ax[:set_ylabel]("speedup of computional time")
  ax[:set_xlabel]("core numbers")
  ax[:legend](fontsize = 12, loc = 4, ncol = 1)
  fig[:savefig]("test$n$t.eps")
end


function main()
  # plot(100, 50, 4)
  # plot(500, 50, 4)
  # plot(1000, 50, 4)
  # plot(2500, 50, 4)
  # plot(5000, 50, 4)
  # plot(7500, 50, 4)
  # plot(10000, 50, 4)
  plot(200000, 50, 4)
end

main()
