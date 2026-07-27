(sub-case simple ((Inheritance $x $y) (Allen SodaDrinker)))
(sub-case nested ((And (Human $x) (Likes $y Soda)) ((var 0) TeaDrinker)))
(sub-case repeated-marker ((Pair (var same) (var same) (var other)) (A B C)))
(sub-case nested-marker ((Outer (var left) (Inner (var right) (var left))) (A B C)))
(sub-case exhausted ((Pair (var first) (var second) (var third)) (A)))

(exec 0
  (, (sub-case $id $case))
  (O (pure (sub-result $id $out) $out
       (substitute (' $case)))))