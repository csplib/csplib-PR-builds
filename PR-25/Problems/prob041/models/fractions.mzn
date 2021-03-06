% 
% Fractions problem in MiniZinc.
%
% Prolog benchmark problem (BProlog)
% """
% Find distinct non-zero digits such that the following equation holds:
%        A        D        G
%     ------  + ----- + ------  = 1
%       B*C      E*F      H*I
% """

% 
% This MiniZinc model was created by Hakan Kjellerstrand, hakank@gmail.com
% See also my MiniZinc page: http://www.hakank.org/minizinc
%

% Licenced under CC-BY-4.0 : http://creativecommons.org/licenses/by/4.0/

% 8 Solutions:
% [7, 2, 4, 5, 8, 9, 1, 3, 6]
% [7, 2, 4, 5, 8, 9, 1, 6, 3]
% [7, 2, 4, 5, 9, 8, 1, 3, 6]
% [7, 2, 4, 5, 9, 8, 1, 6, 3]
% [7, 4, 2, 5, 8, 9, 1, 3, 6]
% [7, 4, 2, 5, 8, 9, 1, 6, 3]
% [7, 4, 2, 5, 9, 8, 1, 3, 6]
% [7, 4, 2, 5, 9, 8, 1, 6, 3]



include "globals.mzn"; 

var 1..9: A;
var 1..9: B;
var 1..9: C;
var 1..9: D;
var 1..9: E;
var 1..9: F;
var 1..9: G;
var 1..9: H;
var 1..9: I;
array[1..9] of var 1..9: Vars=[A,B,C,D,E,F,G,H,I];

var 1..81: D1;
var 1..81: D2;
var 1..81: D3;



% solve satisfy;
solve :: int_search(Vars ++ [D1,D2,D3], first_fail, indomain_min, complete) satisfy;

constraint
   all_different(Vars) /\
   D1 = B*C /\
   D2 = E*F /\
   D3 = H*I /\
   A*D2*D3 + D*D1*D3 + G*D1*D2 = D1*D2*D3 /\
   % break the symmetry
   A*D2 >= D*D1 /\
   D*D3 >= G*D2 /\
   %redundant constraints
   3*A >= D1 /\
   3*G <= D2

;

output [
  show(Vars), "\n"
]
;