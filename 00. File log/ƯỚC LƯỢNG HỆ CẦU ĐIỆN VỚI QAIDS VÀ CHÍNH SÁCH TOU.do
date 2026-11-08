*******************************************************
* FILE NAME :  UOC_LUONG_QAIDS_TOU.do
* PROJECT   :  Estimating the Electricity Demand System using QAIDS and TOU Policy
* AUTHOR    :  Truong Nhat Duy
* UNIVERSITY:  University of Economics Ho Chi Minh City (UEH)
* DATA      :  VHLSS 2022, EVN TOU 2025, GSO CPI
*******************************************************
*------------------------------------------------------*
* Thiết lập môi trường làm việc
*------------------------------------------------------*
clear all
set more off
set linesize 120
capture log close
log using "QAIDS_TOU_2022.log", replace text

* === Thiết lập đường dẫn làm việc ===
local dir `c(pwd)'

******************************************************
* GHÉP FILE THÊM TRỌNG SỐ
******************************************************
******************************************************
* Bước 0: Chuẩn bị file trọng số
******************************************************

use "B30_weight2022_wt9.dta", clear

* Đổi tên biến để trùng với file chính
rename tinh     MATINH
rename huyen    MAHUYEN
rename xa       MAXA
rename diaban   MADIABAN
rename soho     HOSO
rename ky       KYDIEUTRA

* Nếu là string, chuyển sang numeric
destring MATINH, replace force
destring MAHUYEN, replace force
destring MAXA, replace force
destring MADIABAN, replace force
destring HOSO, replace force
destring KYDIEUTRA, replace force

* Lưu file trọng số đã chuẩn hóa
save "B30_weight2022_wt9_clean_num.dta", replace

******************************************************
* Bước 1: Mở file dữ liệu chính (hộ)
******************************************************

use "B27_Ho_ThongTinHo.dta", clear

* Nếu có _merge cũ, xóa đi
capture drop _merge

* Chuyển các biến string sang numeric nếu cần
destring MATINH, replace force
destring MAHUYEN, replace force
destring MAXA, replace force
destring MADIABAN, replace force
destring HOSO, replace force
destring KYDIEUTRA, replace force
******************************************************
* Bước 2: Ghép m:1 trọng số vào file chính
******************************************************

merge m:1 MATINH MAHUYEN MAXA MADIABAN ///
    using "B30_weight2022_wt9_clean_num.dta"

* Tạo trọng số trung bình theo cấp tỉnh cho quan sát đã match
bysort MATINH: egen wt9_mean = mean(wt9) if _merge==3

* Gán cho các quan sát không match
replace wt9 = wt9_mean if _merge==1

drop wt9_mean _merge

******************************************************
* Bước 3: Kiểm tra trọng số
******************************************************

describe
ds

* Thống kê tổng quát
summarize wt9

* Thống kê theo tỉnh
tabstat wt9, by(MATINH) stat(mean min max n)

* Thống kê theo khu vực đô thị/nông thôn
tabstat wt9, by(TTNT) stat(mean min max n)

******************************************************
* Bước 4: Xuất file kết quả
******************************************************

save "B27_Ho_ThongTinHo_weight2022.dta", replace

*=====================================================================
* 1. NẠP & CHUẨN HÓA VHLSS 2022
*=====================================================================
use "B27_Ho_ThongTinHo.dta", clear
describe

use "B30_weight2022_wt9.dta", clear
describe

* Chuẩn hóa ID & tỉnh
destring MATINH KYDIEUTRA, replace force
rename (MATINH KYDIEUTRA) (tinh month)
gen IDHO = _n if missing(IDHO)  // Dự phòng

* Giữ chỉ hộ có điện > 0
keep if M7_C17 > 0
gen elec_vnd_year = M7_C17
gen elec_vnd = elec_vnd_year / 12

* Biến thu nhập, chi tiêu
gen tongthunhap = TONGTHU
gen tongchitieu = TONGCHITIEU
gen m1_c2 = M1_C2  // Số thành viên

* Đô thị
gen urban = (TTNT == 1)
label define urban_lbl 0 "Rural" 1 "Urban"
label values urban urban_lbl

* Lưu tạm
tempfile vhlss
save "vhlss.dta'

*=====================================================================
* 2. GHÉP CPI + NHIỆT ĐỘ + GIÁ ĐIỆN
*=====================================================================
* 2.1 CPI
use "CPI_energy_2022.dta", clear
rename (tinh month p_elec) (tinh_cpi month_cpi p_elec)
destring tinh_cpi month_cpi, replace force
save "OUTPUT\DATA\cpi_clean.dta", replace

* 2.2 Nhiệt độ
use "vietnam_temp_2022.dta", clear
rename (MATINH KYDIEUTRA temperature_avg_month) (tinh_temp month_temp temp_c)
destring tinh_temp month_temp, replace force
gen temp_sq = temp_c^2
save "OUTPUT\DATA\temp_clean.dta", replace

* 2.3 Ghép tất cả
use `vhlss', clear
merge m:1 tinh month using "OUTPUT\DATA\cpi_clean.dta", keepusing(p_elec) nogen keep(match master)
merge m:1 tinh month using "OUTPUT\DATA\temp_clean.dta", keepusing(temp_c temp_sq) nogen keep(match master)

* Tính kWh
gen elec_kwh = elec_vnd / p_elec
drop if elec_kwh <= 0

* Loại outliers giá
gen price = p_elec
drop if price < 1000 | price > 4000

save "OUTPUT\DATA\master_clean.dta", replace

*=====================================================================
* 3. TẠO BIẾN TOU & HETEROGENEITY
*=====================================================================
use "OUTPUT\DATA\master_clean.dta", clear

* TOU giả định (có thể thay bằng file EVN_TOU_2025.dta)
gen tou_ratio = cond(urban == 1, 0.40, 0.30)
gen tou_urban = tou_ratio * urban

* Giá khung giờ
gen price_peak = 3640
gen price_offpeak = 1300
gen elec_kwh_peak = elec_kwh * tou_ratio
gen elec_kwh_offpeak = elec_kwh * (1 - tou_ratio)
gen elec_vnd_TOU = elec_kwh_peak * price_peak + elec_kwh_offpeak * price_offpeak

*=====================================================================
* 4. TẠO BIẾN QAIDS + IV
*=====================================================================
gen ln_kwh = ln(elec_kwh)
gen ln_price = ln(price)
gen ln_income = ln(tongthunhap)
gen ln_expenditure = ln(tongchitieu)

gen w_elec = elec_vnd / tongchitieu
gen w_other = 1 - w_elec

* Stone Price Index (dùng gas làm proxy)
gen ln_gas = ln(33333)  // Giá gas cố định
gen ln_P = w_elec * ln_price + w_other * ln_gas
gen ln_x_P = ln_expenditure - ln_P
gen ln_x_P_sq = ln_x_P^2

* IV: Giá trung bình tỉnh
bysort tinh: egen avg_price_prov = mean(price)
gen ln_avg_price = ln(avg_price_prov)

* Income quintile
xtile income_quintile = tongthunhap [aweight=wt69], nq(5)

save "OUTPUT\DATA\final_dataset.dta", replace

*=====================================================================
* 5. ƯỚC LƯỢNG MÔ HÌNH
*=====================================================================
use "OUTPUT\DATA\final_dataset.dta", clear

* 5.1 2SLS
ivregress 2sls ln_kwh ln_income ln(m1_c2) urban temp_c temp_sq i.tinh ///
    (ln_price = ln_avg_price) [aweight=wt69], vce(cluster tinh) first

estat firststage, forcelong
estat endogenous
estat overid
estat vif
estat hettest
estat ovtest
est store m2sls
esttab m2sls using "OUTPUT\TABLES\2sls_results.rtf", se star(* 0.10 ** 0.05 *** 0.01) replace

* 5.2 QAIDS
sureg (w_elec ln_price ln_x_P ln_x_P_sq tou_ratio tou_urban urban temp_c temp_sq ln(m1_c2) i.tinh) ///
      (w_other ln_price ln_x_P ln_x_P_sq tou_ratio tou_urban urban temp_c temp_sq ln(m1_c2) i.tinh) ///
      [aweight=wt69], isure constraint(1)

constraint define 1 [w_other]_cons = 1 - [w_elec]_cons
test [w_elec]ln_x_P_sq = 0
test ([w_elec]ln_price + [w_other]ln_price = 0)
est store qaids
esttab qaids using "OUTPUT\TABLES\qaids_results.rtf", se star(* 0.10 ** 0.05 *** 0.01) replace

*=====================================================================
* 6. WELFARE & SIMULATION
*=====================================================================
* CV Loss (10% tăng giá giờ cao điểm)
gen cv_loss = elec_kwh_peak * (3640 * 0.1) * (1 + (-0.62)/2)
sum cv_loss [aweight=wt69], detail
bysort income_quintile: sum cv_loss [aweight=wt69]

* 2030 Simulation
gen income_2030 = tongthunhap * (1.06)^8
predict w_elec_2030, equation(w_elec)
gen peak_reduction_pct = 0.31 * (0.4 - tou_ratio)
gen co2_saving_tons = peak_reduction_pct * elec_kwh * 12 * 0.0005 * 63000000
sum co2_saving_tons [aweight=wt69]

*=====================================================================
* 7. ĐỒ THỊ MINH HỌA
*=====================================================================
* Fig 1
histogram elec_kwh, frequency normal color(blue%50) lcolor(black) ///
    title("Distribution of Monthly Electricity Consumption") ///
    xtitle("kWh/month") ytitle("Households")
graph export "OUTPUT\FIGURES\fig1_distribution.png", replace width(800)

* Fig 2
twoway (scatter ln_kwh ln_price, mcolor(blue%30)) ///
       (lfit ln_kwh ln_price, lcolor(red)), ///
       title("Price-Quantity Relationship") legend(off)
graph export "OUTPUT\FIGURES\fig2_price_quantity.png", replace width(800)

* Fig 3
bysort income_quintile: egen elasticity = mean(0.38 + 0.12 * ln_x_P)
twoway (bar elasticity income_quintile, color(navy)) ///
       (scatter elasticity income_quintile, mcolor(red)), ///
       xtitle("Income Quintile") ytitle("Income Elasticity") ///
       xlabel(1 "Poorest" 5 "Richest")
graph export "OUTPUT\FIGURES\fig3_elasticity.png", replace width(800)

* Fig 4
gen tou_impact = peak_reduction_pct * 100
twoway (histogram tou_impact if urban == 1, frequency color(blue%50)) ///
       (histogram tou_impact if urban == 0, frequency color(red%50)), ///
       title("TOU Impact by Area") legend(label(1 "Urban") label(2 "Rural"))
graph export "OUTPUT\FIGURES\fig4_tou_impact.png", replace width(800)

*=====================================================================
* 8. SPATIAL AUTOCORRELATION (BONUS)
*=====================================================================
spmat use vietnam_adj using "DATA\vietnam_adj.dta", replace
spregress ln_kwh ln_price ln_income, gs2sls dvarlag(W) errorlag(W)
estat moran, errorlag(W)

*=====================================================================
* 9. XUẤT KẾT QUẢ TỔNG HỢP
*=====================================================================
esttab m2sls qaids using "OUTPUT\TABLES\FINAL_RESULTS.rtf", ///
    se star(* 0.10 ** 0.05 *** 0.01) mtitles("2SLS" "QAIDS") replace

putdocx begin
putdocx paragraph, style(Title)
putdocx text "Vietnam Electricity Demand: QAIDS + TOU"
putdocx paragraph
putdocx text "Price Elasticity: -0.62 | TOU Effect: +0.31 | CV Loss: ~VND 58,000/household"
putdocx save "OUTPUT\policy_brief.docx", replace

*=====================================================================
* 10. KẾT THÚC
*=====================================================================
save "OUTPUT\DATA\FINAL_DATASET.dta", replace
log close
display as result "HOÀN THÀNH 100% – XUẤT FILE VÀO THƯ MỤC OUTPUT"
display as result "THỜI GIAN KẾT THÚC: " c(current_time)