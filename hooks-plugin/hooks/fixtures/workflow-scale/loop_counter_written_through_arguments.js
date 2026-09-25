// arguments[0]-- writes the parameter the loop counts with, so the stated 20 stands
function run(i) { for (; i < 20; i += 2) { agent("x" + i); arguments[0]-- } }
run(0);
