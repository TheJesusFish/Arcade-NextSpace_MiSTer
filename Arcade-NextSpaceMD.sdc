derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

# fx68k: paths between phi-enabled registers (enables at least 4 clk_sys apart)
set_multicycle_path -start -setup -from [get_keepers *fx68k:*|Ir[*]] -to [get_keepers *fx68k:*|microAddr[*]] 2
set_multicycle_path -start -hold  -from [get_keepers *fx68k:*|Ir[*]] -to [get_keepers *fx68k:*|microAddr[*]] 1
set_multicycle_path -start -setup -from [get_keepers *fx68k:*|Ir[*]] -to [get_keepers *fx68k:*|nanoAddr[*]] 2
set_multicycle_path -start -hold  -from [get_keepers *fx68k:*|Ir[*]] -to [get_keepers *fx68k:*|nanoAddr[*]] 1
set_multicycle_path -start -setup -from {*|nanoLatch[*]}        -to {*|excUnit|alu|pswCcr[*]} 2
set_multicycle_path -start -hold  -from {*|nanoLatch[*]}        -to {*|excUnit|alu|pswCcr[*]} 1
set_multicycle_path -start -setup -from {*|excUnit|alu|oper[*]} -to {*|excUnit|alu|pswCcr[*]} 2
set_multicycle_path -start -hold  -from {*|excUnit|alu|oper[*]} -to {*|excUnit|alu|pswCcr[*]} 1
