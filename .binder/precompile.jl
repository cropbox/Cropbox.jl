using Cropbox

@system S(Controller) begin
    a => 1 ~ preserve
    b(a) ~ track
    c(b) ~ accumulate
end
r = simulate(S; verbose=false);
plot(r, :tick, :c, backend=:UnicodePlots);
plot(r, :tick, :c, backend=:Gadfly);
