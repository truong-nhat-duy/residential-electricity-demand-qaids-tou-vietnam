*******************************************************
* FILE NAME :  UOC_LUONG_QAIDS_TOU.do
* PROJECT   :  Estimating the Electricity Demand System using QAIDS and TOU Policy
* AUTHOR    :  Truong Nhat Duy
* UNIVERSITY:  University of Economics Ho Chi Minh City (UEH)
* DATA      :  VHLSS 2022, EVN TOU 2025, GSO CPI, World Bank Climate Knowledge Portal
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

*******************************************************
* NẠP FILE GHÉP NỐI FILE
*******************************************************
*******************************************************
* BƯỚC 1: NẠP FILE VHLSS HỘ GIA ĐÌNH
*******************************************************
use "B27_Ho_ThongTinHo.dta", clear
* --- Chuẩn hóa biến tỉnh và tháng ---
destring MATINH, replace force
destring KYDIEUTRA, replace force
* --- Loại bỏ các giá trị điện <=0 và tính trung bình hàng tháng ---
keep if M7_C17 > 0
gen elec_vnd_monthly = M7_C17 / 12
* Kiểm tra dữ liệu
summarize elec_vnd_monthly
duplicates report IDHO
sort IDHO
* Lưu file trung gian
tempfile VHLSS_clean
save "VHLSS_clean.dta", replace

*******************************************************
* BƯỚC 2: GHÉP GIÁ ĐIỆN CPI 2022
*******************************************************
* --- Chuẩn hóa file CPI ---
use "CPI_energy_2022.dta", clear
describe
rename tinh MATINH
rename month KYDIEUTRA
destring MATINH, replace force
destring KYDIEUTRA, replace force
* Lưu file đã chuẩn hóa
save "CPI_energy_clean.dta", replace

* --- Quay lại dữ liệu VHLSS ---
use "VHLSS_clean.dta", clear

* Merge với CPI
merge m:1 MATINH KYDIEUTRA using "CPI_energy_clean.dta"

* Kiểm tra kết quả merge
tab _merge
list MATINH KYDIEUTRA elec_vnd_monthly if _merge==1, sepby(MATINH)

* Lưu file trung gian sau merge CPI
tempfile VHLSS_CPI
save "VHLSS_CPI.dta", replace
describe

*******************************************************
* BƯỚC 3: GHÉP NHIỆT ĐỘ 2022
*******************************************************
* --- Chuẩn hóa file nhiệt độ ---
use "vietnam_temp_2022.dta", clear
rename temperature_avg_month temp_avg
destring MATINH, replace force
destring KYDIEUTRA, replace force
save "vietnam_temp_2022_clean.dta", replace
* --- Quay lại dữ liệu VHLSS đã ghép CPI ---
use "VHLSS_CPI.dta", clear
* Merge nhiệt độ
drop _merge
merge m:1 MATINH KYDIEUTRA using "vietnam_temp_2022_clean.dta"
* Kiểm tra merge
tab _merge
list MATINH KYDIEUTRA temp_avg if _merge==1, sepby(MATINH)
* Kiểm tra tổng quan nhiệt độ
summarize temp_avg
* Lưu file cuối cùng
save "VHLSS2022_energy_temp_final.dta", replace

******************************************************
* 1. Thống kê nhanh các biến số
******************************************************
describe
summarize
summarize, detail  // chi tiết min, max, mean, sd

******************************************************
* 1. Thống kê nhanh các biến số quan trọng
******************************************************
* Kiểm tra thông tin cơ bản của các biến
describe elec_vnd_monthly TONGCHITIEU TONGTHU p_elec TTNT
* Thống kê tóm tắt và chi tiết để kiểm tra min, max, mean, sd
summarize elec_vnd_monthly TONGCHITIEU TONGTHU p_elec, detail

*******************************************************
* CHUẨN HÓA DỮ LIỆU & TẠO BIẾN CẦN THIẾT CHO MÔ HÌNH HỒI QUY
*******************************************************
* Chuẩn hóa chi tiêu, thu nhập hộ gia đình về VND:
* TONGCHITIEU và TONGTHU hiện đang là giá trị năm quy về tháng:
gen TONGCHITIEU_monthly = TONGCHITIEU / 12

gen TONGTHU_monthly = TONGTHU / 12

* Chuẩn hóa về VND (trường hợp gốc là nghìn đồng)
* (Ghi chú: Trong VHLSS 2022, TONGCHITIEU và TONGTHU  DVT: 1.000 VND/năm)
gen TONGCHITIEU_monthly_VND = TONGCHITIEU_monthly * 1000

gen TONGTHU_monthly_VND = TONGTHU_monthly * 1000

replace elec_vnd_monthly = elec_vnd_monthly * 1000

******************************************************
* Tạo tỷ trọng chi tiêu điện (w_elec)
******************************************************
* Vì chi tiêu điện là hàng tháng, nên cần quy đổi về cùng đơn vị với chi tiêu năm
* Tạo w_elec = tỷ lệ điện của từng hộ:Tỷ trọng chi tiêu điện hàng tháng
replace w_elec = elec_vnd_monthly / TONGCHITIEU_monthly_VND
gen w_other = 1 - w_elec
gen ln_w_elec = ln(w_elec)

* Kiểm tra biến vừa tạo
summarize elec_vnd_monthly TONGCHITIEU_monthly_VND TONGTHU_monthly_VND w_elec w_other

******************************************************
* 2.1. Tạo biến giá điện và lượng điện tiêu thụ
* tính và tạo biến lượng điện tiêu thụ (kwh/Tháng):
******************************************************
* Ước tính điện năng tiêu thụ (kWh/tháng) từ tiền điện từ Biểu giá điện sinh hoạt EVN năm 2022 bậc thang
******************************************************
******************************************************
* TÍNH NGƯỢC LƯỢNG ĐIỆN TIÊU THỤ (kWh/tháng) TỪ TIỀN ĐIỆN
******************************************************

* 1. Khai báo giá điện bậc thang
local p1 = 1728
local p2 = 1786
local p3 = 2074
local p4 = 2612
local p5 = 2919
local p6 = 3015

* 2. Khai báo ngưỡng cộng dồn tiền từng bậc (đúng theo tổng tiền tích lũy đến hết mỗi bậc)
local t1 = 50 * `p1'
local t2 = `t1' + 50 * `p2'
local t3 = `t2' + 100 * `p3'
local t4 = `t3' + 100 * `p4'
local t5 = `t4' + 100 * `p5'

* 3. Khởi tạo biến kết quả
replace elec_kwh = .

* 4. Tính lượng điện tiêu thụ theo tiền điện từng bậc:
replace elec_kwh = cond(elec_vnd_monthly <= `t1', elec_vnd_monthly / `p1', 50)
replace elec_kwh = cond(elec_vnd_monthly > `t1' & elec_vnd_monthly <= `t2', 50 + (elec_vnd_monthly - `t1') / `p2', elec_kwh)
replace elec_kwh = cond(elec_vnd_monthly > `t2' & elec_vnd_monthly <= `t3', 100 + (elec_vnd_monthly - `t2') / `p3', elec_kwh)
replace elec_kwh = cond(elec_vnd_monthly > `t3' & elec_vnd_monthly <= `t4', 200 + (elec_vnd_monthly - `t3') / `p4', elec_kwh)
replace elec_kwh = cond(elec_vnd_monthly > `t4' & elec_vnd_monthly <= `t5', 300 + (elec_vnd_monthly - `t4') / `p5', elec_kwh)
replace elec_kwh = cond(elec_vnd_monthly > `t5', 400 + (elec_vnd_monthly - `t5') / `p6', elec_kwh)

* 5. Kiểm tra kết quả
summ elec_kwh, detail
summarize elec_kwh, detail
* Kiểm tra các hộ cực đại
list elec_vnd_monthly elec_kwh if elec_kwh > 10000

histogram elec_kwh, width(50) frequency title("Histogram: Lượng điện tiêu thụ (kWh)")

* Boxplot cho lượng điện tiêu thụ
graph box elec_kwh, title("Boxplot: Lượng điện tiêu thụ (kWh/tháng)") ytitle("kWh") 

graph box elec_kwh if elec_kwh < 5000, title("Boxplot: Lượng điện tiêu thụ <5000 kWh")

* sau khi kiểm tra thì có nhiều hộ dùng điện cao bất thường, xử lý biến outlier và so sánh:
* Xác định percentile 99
summarize elec_kwh, detail
local p99 = r(p99)
* Winsorize: giới hạn giá trị trên percentile 99
replace elec_kwh = `p99' if elec_kwh > `p99'
* Hoặc loại bỏ hoàn toàn các hộ cực đại
drop if elec_kwh > 10000

******************************************************
* TẠO BIẾN GIÁ ĐIỆN (VND/Tháng):
******************************************************
******************************************************
* (A) GIÁ TRUNG BÌNH (Average Price - AP)
******************************************************
gen price_ap = elec_vnd_monthly / elec_kwh
replace price_ap = . if price_ap <= 0 | price_ap > 10000   // loại giá bất hợp lý
gen ln_price_ap = ln(price_ap)

* Tạo giá trung bình trong tỉnh (Average price by province)
bysort MATINH: egen avg_price_prov = mean(price_ap)
gen ln_avg_price_prov = ln(avg_price_prov)

* Loại hộ i ra khỏi trung bình (Instrument cho IV)
bysort MATINH: egen total_price_ap = total(price_ap)
bysort MATINH: egen n_ap = count(price_ap)
gen avg_price_excl_ap = (total_price_ap - price_ap) / (n_ap - 1)
gen ln_avg_price_excl_ap = ln(avg_price_excl_ap)

******************************************************
* (B) GIÁ CẬN BIÊN (Marginal Price - MP)
******************************************************
gen price_mp = .
replace price_mp = 1728 if elec_kwh <= 50
replace price_mp = 1786 if elec_kwh > 50 & elec_kwh <= 100
replace price_mp = 2074 if elec_kwh > 100 & elec_kwh <= 200
replace price_mp = 2612 if elec_kwh > 200 & elec_kwh <= 300
replace price_mp = 2919 if elec_kwh > 300 & elec_kwh <= 400
replace price_mp = 3015 if elec_kwh > 400
gen ln_price_mp = ln(price_mp)

* Tạo IV cho MP: trung bình tỉnh loại hộ i
bysort MATINH: egen total_price_mp = total(price_mp)
bysort MATINH: egen n_mp = count(price_mp)
gen avg_price_excl_mp = (total_price_mp - price_mp) / (n_mp - 1)
gen ln_avg_price_excl_mp = ln(avg_price_excl_mp)

******************************************************
* thống kê nhanh:
summarize elec_kwh price_ap price_mp ln_price_ap ln_price_mp ln_avg_price_excl_ap ln_avg_price_excl_mp
summarize elec_kwh, detail
summarize ln_price_ap, detail
summarize ln_price_mp, detail

* Winsorize elec_kwh
summarize elec_kwh, detail
local p1 = r(p1)
local p99 = r(p99)
gen elec_kwh_w = elec_kwh
replace elec_kwh_w = `p1' if elec_kwh < `p1'
replace elec_kwh_w = `p99' if elec_kwh > `p99'

* Winsorize ln_price_ap
summarize ln_price_ap, detail
local p1 = r(p1)
local p99 = r(p99)
gen ln_price_ap_w = ln_price_ap
replace ln_price_ap_w = `p1' if ln_price_ap < `p1'
replace ln_price_ap_w = `p99' if ln_price_ap > `p99'

* Winsorize ln_price_mp
summarize ln_price_mp, detail
local p1 = r(p1)
local p99 = r(p99)
gen ln_price_mp_w = ln_price_mp
replace ln_price_mp_w = `p1' if ln_price_mp < `p1'
replace ln_price_mp_w = `p99' if ln_price_mp > `p99'

summarize ln_avg_price_excl_mp 
histogram ln_avg_price_excl_mp, percent normal title("Histogram ln_avg_price_excl_mp")

* đồ thị các biến giá
summarize ln_avg_price_excl_ap 
histogram ln_avg_price_excl_ap, percent normal title("Histogram ln_avg_price_excl_ap")

histogram price_ap, percent normal title("Histogram price_ap")

histogram price_mp, percent normal title("Histogram price_mp")

histogram ln_price_mp, percent normal ///
    title("Histogram ln_price_mp") ///
     xlabel(, grid)
	
histogram ln_price_ap, percent normal ///
    title("Histogram ln_price_ap") ///
    xlabel(, grid)

******************************************************
* 3. Tạo biến log (phục vụ mô hình QAIDS/2SLS)
******************************************************
* Tạo các biến log:
gen ln_kwh = ln(elec_kwh) if elec_kwh > 0

* Vẽ histogram ln_kwh với đường mật độ chuẩn
histogram ln_kwh, width(0.2) normal ///
    frequency ///
    title("Histogram: Phân phối ln_kwh") ///
    xlabel(, grid)
	
* đồ thị Histogram phân phối log (kiểm tra lại phân phối)	
kdensity ln_kwh, title("Density plot: ln_kwh") xtitle("ln(kWh)") ytitle("Density")

* đồ thị Boxplot log điện tiêu thụ:
graph box ln_kwh, title("Boxplot: ln_kWh") ytitle("ln(kWh)")

*  tạo biến ln_income
gen ln_income = ln(TONGTHU_monthly_VND) if TONGTHU_monthly_VND > 0

* Tạo biến ln_expenditure

gen ln_expenditure = ln(TONGCHITIEU_monthly_VND) if TONGCHITIEU_monthly_VND > 0

* Tạo biến ln_price
gen ln_x_P = ln_expenditure - ln_price_ap

* Tạo thành phần bình phương
gen ln_x_P_sq = ln_x_P^2

* Kiểm tra:
sum ln_kwh ln_price_ap ln_income ln_expenditure ln_x_P ln_x_P_sq

******************************************************
* 4. Tạo biến phân loại khu vực (urban/rural) (1 = Urban, 0 = Rural)
******************************************************
* Tạo biến numeric urban 
gen urban = (TTNT == 1)
* Đảm bảo urban là numeric (byte)
destring urban, replace force   // không bắt buộc nếu đã là numeric
* Gán nhãn
label define urban_lbl 0 "Rural" 1 "Urban"
label values urban urban_lbl
* Kiểm tra biến vừa tạo
tab urban
codebook urban

******************************************************
* 5. TẠO BIẾN VÙNG THEO CHUẨN VHLSS 2022
* Biến tham chiếu: Red River Delta = 0
******************************************************
* --- Khởi tạo biến region ---
gen region = .   // mặc định missing

* Red River Delta (Đồng bằng sông Hồng): 1–11
replace region = 0 if inlist(MATINH,1,2,3,4,5,6,7,8,9,10,11)
* Northern Midlands & Mountains: 12–21
replace region = 1 if inlist(MATINH,12,13,14,15,16,17,18,19,20,21)
* North Central & Central Coastal: 22–40
replace region = 2 if inlist(MATINH,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40)
* Central Highlands: 41–45
replace region = 3 if inlist(MATINH,41,42,43,44,45,67)
* Southeast (Đông Nam Bộ): 46–52, 62,64,65,66,68,70,79,80
replace region = 4 if inlist(MATINH,46,47,48,49,50,51,52,62,64,65,66,68,70,79,80)
* Mekong Delta: 53–63,72,74,75,77,82,83,84,86,87,89,91,92,93,94,95,96
replace region = 5 if inlist(MATINH,53,54,55,56,57,58,59,60,61,63,72,74,75,77,82,83,84,86,87,89,91,92,93,94,95,96)
* Unknown / Foreign: 98
replace region = 6 if MATINH==98
* --- Gán nhãn cho biến region ---
label define region_lbl 0 "Red River Delta (reference)" ///
                        1 "Northern Midlands & Mountains" ///
                        2 "North Central & Central Coastal" ///
                        3 "Central Highlands" ///
                        4 "Southeast" ///
                        5 "Mekong Delta" ///
                        6 "Unknown/Foreign"
label values region region_lbl
* --- Kiểm tra phân bố ---
tab region, missing
codebook region

list MATINH region if region==.

******************************************************
* 6. TẠO BIẾN MÙA VỤ (MÙA KHÔ = 1, MÙA MƯA = 0)
******************************************************
gen dry_season = .
replace dry_season = 1 if inlist(KYDIEUTRA, 12,1,2,3,4,5)   // tháng mùa khô
replace dry_season = 0 if inlist(KYDIEUTRA, 6,7,8,9,10,11)  // tháng mùa mưa
label define dry_lbl 0 "Wet season" 1 "Dry season"
label values dry_season dry_lbl

* Kiểm tra
tab dry_season
codebook dry_season

******************************************************
* 7. TẠO BIẾN SEASON 4 MÙA (SPRING–WINTER)
******************************************************
gen season = .
replace season = 1 if KYDIEUTRA>=1 & KYDIEUTRA<=3      // Spring
replace season = 2 if KYDIEUTRA>=4 & KYDIEUTRA<=6      // Summer
replace season = 3 if KYDIEUTRA>=7 & KYDIEUTRA<=9      // Autumn
replace season = 0 if KYDIEUTRA>=10 & KYDIEUTRA<=12    // Winter
label define season_lbl 1 "Spring" 2 "Summer" 3 "Autumn" 0 "Winter"
label values season season_lbl

tab season
codebook season

******************************************************
* 8. TẠO BIẾN NHÓM THU NHẬP ((Q1–Q5))
******************************************************
* Divide income (ln_income) into 5 quintiles
xtile income_group = ln_income, n(5)
* Gán nhãn ý nghĩa cho từng nhóm
* Label each quintile
label define income_lbl ///
    1 "Q1 (Poorest)" ///
    2 "Q2" ///
    3 "Q3 (Middle)" ///
    4 "Q4" ///
    5 "Q5 (Richest)"

label values income_group income_lbl
tab income_group

* đặt lại tên nhóm: 
gen income_class = .
replace income_class = 1 if income_group == 1    // Q1 - Poorest
replace income_class = 2 if income_group == 2    // Q2
replace income_class = 0 if income_group == 3    // Q3 - Baseline
replace income_class = 3 if income_group == 4    // Q4
replace income_class = 4 if income_group == 5    // Q5 - Richest
label define class_lbl ///
    0 "Q3 (Baseline)" ///
    1 "Q1 (Poorest)" ///
    2 "Q2" ///
    3 "Q4" ///
    4 "Q5 (Richest)"
label values income_class class_lbl

tab income_class

********************************************************
* 9. TẠO BIẾN GIÁ TOU - giá cao điểm theo Thí điểm Hà Nội & TP.HCM (PILOT):
*******************************************************
* urban = 1 cho TP. HCM và Hà Nội, 0 các tỉnh khác
replace tou_ratio = 0
replace tou_ratio = 0.4 if MATINH==1    // Hà Nội theo VHLSS
replace tou_ratio = 0.4 if MATINH==79   // TP. HCM theo VHLSS
gen tou_urban = tou_ratio
gen tou_urbanXurban = tou_urban * urban
* Kiểm tra
tab tou_urban
tab tou_ratio
summarize tou_ratio

* Giá khung giờ: theo Quyết định 599/QĐ-EVN, 2025: 

gen price_peak = 2934  /// 2,934 VND/kWh

gen price_normal = 1659 /// 1,659 VND/kWh

gen price_offpeak = 1022 /// 1,022 VND/kWh

* Giá trung bình theo TOU
gen price_tou = tou_urban*price_peak + (1-tou_urban)*price_normal
gen ln_price_tou = ln(price_tou)

********************************************************
* 10. Tạo thêm biến công cụ (IV): IV 2: Giá gas, IV 3: Nhiệt độ trung bình tỉnh
*******************************************************
* IV 2: Giá gas tỉnh (exogenous)
bysort MATINH: egen avg_gas_prov = mean(gas_price)
gen ln_gas_prov = ln(avg_gas_prov)

* IV 3: Nhiệt độ trung bình tỉnh
bysort MATINH: egen temp_prov = mean(temp_avg)

* TÍNH kWh CAO ĐIỂM & THẤP ĐIỂM
gen elec_kwh_peak = elec_kwh * tou_ratio
gen elec_kwh_offpeak = elec_kwh * (1 - tou_ratio)

* TÍNH HÓA ĐƠN TOU
gen elec_vnd_TOU = elec_kwh_peak * price_peak + elec_kwh_offpeak * price_offpeak

*******************************************************
* 11. TẠO BIẾN CHÍNH PHÂN TÍCH QAIDS
*******************************************************
* tạo biến giá trung bình có trọng số theo chi tiêu năng lượng chi tiêu cho điện và năng lượng thay thế (gas).
* dùng trong mô hình QAIDS (Quadratic Almost Ideal Demand System):

gen ln_P = w_elec * ln_avg_price_excl_ap + (1 - w_elec) * ln(gas_price)

* Tạo Biến bình phương nhiệt độ
gen temp_sq = temp_avg^2

* Đổi tên cho MATINH:
rename MATINH tinh

* Kiểm tra số quan sát missing cho các biến chính trước khi chạy mô hình:
misstable summarize elec_vnd_monthly elec_kwh ln_kwh temp_avg temp_sq price_ap price_mp ln_price_ap ln_price_mp ln_avg_price_excl_ap ln_avg_price_excl_mp ln_expenditure ln_x_P ln_x_P_sq w_elec tou_ratio 

summarize ln_kwh ln_income ln_w_elec urban temp_avg temp_sq price_ap price_mp ln_price_ap ln_price_mp

* Loại bỏ quan sát missing
drop if missing(ln_price_ap)

* Histogram ln_kwh
histogram ln_kwh, width(0.2) frequency ///
    title("Histogram ln_kwh") ///
    xlabel(, grid)

* Histogram ln_income
histogram ln_income, width(0.2) frequency ///
    title("Histogram ln_income") ///
    xlabel(, grid)

* Histogram ln_w_elec
histogram ln_w_elec, width(0.2) frequency ///
    title("Histogram ln_w_elec") ///
    xlabel(, grid)

******************************************************
* CHUẨN HÓA BIẾN NHIỆT ĐỘ - MEAN CENTERED
******************************************************

* Tính trung bình nhiệt độ
summ temp_avg
gen temp_centered = temp_avg - r(mean)
gen temp_sq_centered = temp_centered^2

* Kiểm tra lại
summ temp_avg temp_centered temp_sq_centered
******************************************************
* Log trọng số hộ
gen ln_wt9 = log(wt9)
*******************************************************
* Thống kê mô tả toàn bộ các biến chính trong mô hình:
*******************************************************
local vars ///
    elec_kwh ln_kwh price_ap price_mp ln_price_ap ln_price_mp ln_avg_price_excl_ap ln_avg_price_excl_mp ///
    ln_income ln_expenditure ln_x_P ln_x_P_sq temp_avg temp_centered temp_sq_centered ///
    w_elec ln_w_elec urban dry_season region income_class tou_urban tou_urbanXurban
* Bảng thống kê mô tả tiêu chuẩn: mean, sd, min, max, p1, p25, p50, p75, p99
foreach v of local vars {
    display "----------------------------------------"
    display "`v'"
    summarize `v', detail
}
* 1. Kiểm tra correlation và multi-collinearity của các biến trong mô hình:
*******************************************************
* ma trận correlation cơ bản:
corr ln_avg_price_excl_ap ln_avg_price_excl_mp ln_income ln_w_elec urban dry_season region temp_avg temp_sq_centered tou_urban tou_urbanXurban

* Ma trận correlation với kiểm định ý nghĩa (p-value)"
pwcorr ln_avg_price_excl_ap ln_avg_price_excl_mp ln_income ln_w_elec urban dry_season region temp_avg temp_sq_centered tou_urban tou_urbanXurban, sig

********** LƯU FILE DỮ LIỆU CUỐI: Data_full.dta **********
save "Data_full.dta", replace

*******************************************************
* 4. ƯỚC LƯỢNG MÔ HÌNH OLS + 2SLS + QAIDS
*******************************************************
*******************************************************
* 7. ƯỚC LƯỢNG MÔ HÌNH OLS
*******************************************************

* ƯỚC LƯỢNG CÁC MÔ HÌNH OLS VÀ SO SÁNH:

reg ln_kwh ln_price_ap ln_income temp_centered temp_sq_centered ///
    urban i.region i.dry_season [aweight=wt9]

reg ln_kwh ln_price_ap ln_income ln_w_elec temp_centered temp_sq_centered ///
    i.urban i.income_class i.region i.dry_season  [aweight=wt9]
	
reg ln_kwh ln_avg_price_excl_ap ln_income ln_w_elec temp_centered temp_sq_centered ///
    i.urban i.income_class i.region i.dry_season  [aweight=wt9]

reg ln_kwh ln_avg_price_excl_ap ln_income ln_w_elec ///
    i.urban i.income_class [aweight=wt9]

reg ln_kwh ln_price_ap ln_income ln_w_elec ///
    i.urban i.income_class [aweight=wt9]
	
* MÔ HÌNH OLS cho R2 và giải thích tốt nhất:

reg ln_kwh ln_price_ap ln_income ln_w_elec temp_centered temp_sq_centered ///
    i.urban i.income_class i.region i.dry_season  [aweight=wt9]

reg ln_kwh ln_price_ap ln_income ln_w_elec ///
    i.urban i.income_class [aweight=wt9]
estimates store ols_model
	
*******************************************************
* 8. ƯỚC LƯỢNG MÔ HÌNH 2SLS
*******************************************************
* First-stage (thăm dò): regress ln_price_mp on instrument + controls
regress ln_price_mp ln_avg_price_excl_mp ln_income ln_w_elec temp_centered temp_sq_centered ///
    urban i.income_class i.region i.dry_season [aweight=wt9], vce(cluster region)

* 3) Thực hiện 2SLS chính thức với ivregress (tùy chọn: hiển thị first-stage):
ivregress 2sls ln_kwh ln_income ln_w_elec urban income_class temp_sq_centered ///
    (ln_price_mp = ln_avg_price_excl_mp) [aweight=wt9], vce(cluster region) first

* First-stage kiểm tra IV mạnh
estat firststage

* Kiểm định nội sinh
ivregress 2sls ln_kwh ln_income ln_w_elec urban dry_season i.region temp_avg temp_sq ///
    (ln_avg_price_excl_ap = ln_avg_price_excl_mp), vce(cluster region)
estat endogenous

* Overidentification test
* Tạo ln_price_neighbor = trung bình ln_price_mp của các tỉnh cùng vùng, loại trừ tỉnh hiện tại
egen ln_price_neighbor = mean(ln_price_mp), by(region)
replace ln_price_neighbor = (ln_price_neighbor* _N - ln_price_mp)/(_N - 1) if _N>1
summ ln_price_neighbor
tab region if missing(ln_price_neighbor)

ivregress 2sls ln_kwh ln_income ln_w_elec temp_centered temp_sq_centered ///
    urban i.income_class i.region i.dry_season ///
    (ln_price_mp = ln_avg_price_excl_mp ln_price_neighbor) ///
    [aweight=wt9], vce(cluster region) first

* Để lấy elasticities (co giãn giá): coefficient của ln_price_mp trong 2SLS là elasticity (∂ln q / ∂ln p).
*    Lưu hệ số và SE:
estimates store iv_model

* White robust SE cho 2SLS:
ivregress 2sls ln_kwh ln_income ln_w_elec temp_centered temp_sq_centered ///
    urban i.income_class i.region i.dry_season ///
    (ln_price_mp = ln_avg_price_excl_mp) [aweight=wt9], vce(robust)

* Ramsey RESET (omitted variables)
predict uhat, resid
summ uhat

********************************************************
* Chạy 2SLS với các IV bổ sung: IV 2: Giá gas, IV 3: Nhiệt độ trung bình tỉnh
********************************************************
ivregress 2sls ln_kwh ln_income ln_w_elec temp_centered temp_sq_centered ///
    urban i.income_class i.region i.dry_season ///
    (ln_price_mp = ln_avg_price_excl_mp ln_gas_prov) ///
    [aweight=wt9], vce(cluster region) first

ivregress 2sls ln_kwh ln_income ln_w_elec ///
    urban i.income_class i.region i.dry_season ///
    (ln_price_mp = ln_avg_price_excl_mp ln_gas_prov) ///
    [aweight=wt9], vce(cluster region) first

ivregress 2sls ln_kwh ln_income ln_w_elec ///
    urban i.income_class i.region i.dry_season ///
    (ln_price_mp = ln_avg_price_excl_mp) ///
    [aweight=wt9], vce(cluster region) first
	
********************************************************
* Mô hình 2SLS tối ưu:
********************************************************
ivregress 2sls ln_kwh ln_income ln_w_elec ///
    urban i.income_class i.region i.dry_season ///
    (ln_price_mp = ln_avg_price_excl_mp) ///
    [aweight=wt9], vce(cluster region) first

* Kiểm tra heteroskedasticity / robust SE đã dùng cluster
* Nếu muốn kiểm tra robust SE riêng:
ivregress 2sls ln_kwh ln_income ln_w_elec ///
    urban i.income_class i.region i.dry_season ///
    (ln_price_mp = ln_avg_price_excl_mp) ///
    [aweight=wt9], vce(robust)
	
********************************************************
* So sánh OLS tối ưu và 2SLS tối ưu
********************************************************
* Lấy coefficient của ln_price_mp để so sánh OLS vs 2SLS
eststo ols: reg ln_kwh ln_price_mp ln_income ln_w_elec ///
    urban i.income_class i.region i.dry_season [aweight=wt9], vce(cluster region)

eststo iv: ivregress 2sls ln_kwh ln_income ln_w_elec ///
    urban i.income_class i.region i.dry_season ///
    (ln_price_mp = ln_avg_price_excl_mp) ///
    [aweight=wt9], vce(cluster region)

esttab ols iv, se label star(* 0.10 ** 0.05 *** 0.01) ///
    title("OLS vs 2SLS Comparison") replace

********************************************************
* Optional: kiểm tra đồ thị first-stage
********************************************************
predict ln_price_hat if e(sample), xb
scatter ln_price_mp ln_price_hat

* Weak instrument test
estat firststage

*******************************************************
* 9. ƯỚC LƯỢNG MÔ HÌNH QAIDS (SUR)
*******************************************************
sureg (w_elec = ln_P ln_x_P ln_x_P_sq tou_urban temp_centered temp_sq_centered ln_income urban dry_season i.region i.income_class) ///
[aweight=wt9], isure

sureg (w_elec = ln_P ln_x_P ln_x_P_sq ln_income urban dry_season i.region) [aweight=wt9], isure

sureg (w_elec = ln_P ln_x_P ln_x_P_sq tou_urban temp_centered temp_sq_centered ln_income urban dry_season i.region) [aweight=wt9], isure

sureg (w_elec = ln_P ln_x_P ln_x_P_sq ln_income urban dry_season i.region i.income_class) ///
[aweight=wt9], isure

sureg (w_elec = ln_P ln_x_P ln_x_P_sq tou_urban temp_centered temp_sq_centered ///
ln_income urban dry_season i.region i.income_class) [aweight=wt9], isure

gen ln_P_ln_income = ln_P * ln_income

ivregress 2sls w_elec ln_income urban dry_season i.region i.income_class ///
(ln_price_ap = ln_avg_price_excl_ap) [aweight=wt9], vce(cluster region)
 
gen tou_urban_x_urban = tou_urban * urban
gen temp_x_lnP = temp_centered * ln_P
sureg (w_elec = ln_P ln_x_P ln_x_P_sq ln_income tou_urban temp_centered temp_sq_centered ///
temp_x_lnP tou_urban_x_urban ln_income urban dry_season i.region i.income_class) [aweight=wt9], isure

* Mô hình QAIDS (SUR) tối ưu:
sureg (w_elec = ln_P ln_x_P ln_x_P_sq tou_urban temp_centered temp_sq_centered ln_income urban dry_season i.region i.income_class) [aweight=wt9], isure

sureg (w_elec = ln_P ln_x_P ln_x_P_sq tou_urban temp_centered temp_sq_centered ln_income urban dry_season i.region i.income_class) [aweight=wt9], isure
* Kiểm định Breusch-Pagan
est store qaids_model

* Kiểm định bậc hai λ ≠ 0
test [w_elec]ln_x_P_sq = 0

* Chi2(1) =  0.16, p = 0.6868 (thành phần bình phương ln_x_P_sq không cần thiết trong mô hình, loại bỏ để tinh gọn mô hình QAIDS)
sureg (w_elec = ln_P ln_x_P tou_urban temp_centered temp_sq_centered ln_income urban dry_season i.region i.income_class) [aweight=wt9], isure

* Kiểm tra residuals / outliers
predict resid_w_elec, resid
summarize resid_w_elec
histogram resid_w_elec, normal width(0.01)
list elec_kwh elec_vnd_monthly resid_w_elec if abs(resid_w_elec) > 0.05

* Breusch–Pagan / Cook–Weisberg test (heteroskedasticity)
sureg (w_elec = ln_P ln_x_P ln_x_P_sq tou_urban temp_centered temp_sq_centered ln_income urban dry_season i.region i.income_class) [aweight=wt9], isure
predict ehat, residuals
sktest ehat
swilk ehat

* Kiểm định dạng hàm (Functional form): Ramsey RESET
reg w_elec ln_P ln_x_P ln_x_P_sq tou_urban temp_centered temp_sq_centered ln_income urban dry_season i.region i.income_class [aweight=wt9]
ovtest

* Kiểm định Wald cho temp_sq_centered
test temp_sq_centered = 0
test temp_centered temp_sq_centered

* Kiểm tra đa thức QAIDS (Quadratic term significance)
test ln_x_P_sq

* Lưu QAIDS
est store qaids_model


* Mô hình đầy đủ
sureg (w_elec = ln_P ln_x_P tou_urban temp_centered temp_sq_centered ln_income urban dry_season i.region i.income_class) [aweight=wt9], isure

* Loại bỏ biến vùng miền
sureg (w_elec = ln_P ln_x_P tou_urban temp_centered temp_sq_centered ln_income urban dry_season i.income_class) [aweight=wt9], isure

* Loại bỏ biến mùa khô
sureg (w_elec = ln_P ln_x_P tou_urban temp_centered temp_sq_centered ln_income urban i.region i.income_class) [aweight=wt9], isure

* Loại bỏ biến khí hậu
sureg (w_elec = ln_P ln_x_P tou_urban ln_income urban dry_season i.region i.income_class) [aweight=wt9], isure

* Kiểm tra phân phối
summarize w_elec
kdensity w_elec

* Vẽ histogram với đường chuẩn
histogram w_elec, normal

* Kiểm tra outlier
summarize w_elec, detail

*******************************************************
* 1. CALCULATE ELASTICITIES
*******************************************************
* --- Variables ---
* w_elec      : share of electricity expenditure
* ln_P        : log price of electricity
* ln_x_P      : log total expenditure on electricity
* ln_x_P_sq   : square of ln_x_P
* ln_income   : log income
* coefficients from sureg: _b[ln_P], _b[ln_x_P], _b[ln_x_P_sq], _b[ln_income]

* --- Marshallian (Uncompensated) Price Elasticity ---
gen price_elasticity_marshall = (_b[ln_P] + 2*_b[ln_x_P_sq]*ln_x_P) / w_elec

* --- Income Elasticity ---
gen income_elasticity = 1 + (_b[ln_income] / w_elec)

* --- Hicksian (Compensated) Price Elasticity ---
gen price_elasticity_hicks = price_elasticity_marshall + w_elec * income_elasticity

* Kết quả:
* --- Trung bình toàn mẫu ---
summarize price_elasticity_marshall price_elasticity_hicks income_elasticity

* --- Trung bình theo vùng ---
preserve
collapse (mean) price_elasticity_marshall price_elasticity_hicks income_elasticity, by(region)
tabstat price_elasticity_marshall price_elasticity_hicks income_elasticity, by(region) statistics(mean sd min max)
restore

* --- Trung bình theo nhóm thu nhập ---
preserve
* Collapse tính trung bình theo nhóm thu nhập
collapse (mean) price_elasticity_marshall price_elasticity_hicks income_elasticity, by(income_class)
* Hiển thị bảng kết quả chi tiết
tabstat price_elasticity_marshall price_elasticity_hicks income_elasticity, ///
    by(income_class) statistics(mean sd min max) columns(statistics)
restore
	
* --- Xem histogram phân phối elasticities ---
histogram price_elasticity_marshall, percent normal
histogram price_elasticity_hicks, percent normal
histogram income_elasticity, percent normal

summarize price_elasticity_marshall price_elasticity_hicks income_elasticity, detail

*******************************************************
* 1. XỬ LÝ OUTLIERS TRONG QAIDS ELASTICITIES
*******************************************************

* Cài đặt gói winsor2 nếu chưa có
ssc install winsor2, replace
*******************************************************
* 2. XỬ LÝ OUTLIERS bằng Winsorize 1% và 99%
*******************************************************
* Tạo biến mới giữ dữ liệu gốc
gen price_elasticity_marshall_w = price_elasticity_marshall
gen price_elasticity_hicks_w   = price_elasticity_hicks
gen income_elasticity_w         = income_elasticity

* Winsorize biến price_elasticity_marshall_w ở 1% và 99%
winsor2 price_elasticity_marshall_w, cuts(1 99)
winsor2 price_elasticity_hicks_w,   cuts(1 99)
winsor2 income_elasticity_w,         cuts(1 99)

*******************************************************
* 3. SUMMARY TOÀN MẪU (sau Winsorize)
*******************************************************
summarize price_elasticity_marshall_w price_elasticity_hicks_w income_elasticity_w, detail
*******************************************************
* 4. SUMMARY THEO VÙNG
*******************************************************
preserve
collapse (mean) price_elasticity_marshall_w price_elasticity_hicks_w income_elasticity_w, by(region)
tabstat price_elasticity_marshall_w price_elasticity_hicks_w income_elasticity_w, ///
    by(region) statistics(mean sd min max) columns(statistics)
restore
*******************************************************
* 5. SUMMARY THEO NHÓM THU NHẬP
*******************************************************
preserve
collapse (mean) price_elasticity_marshall_w price_elasticity_hicks_w income_elasticity_w, by(income_class)
tabstat price_elasticity_marshall_w price_elasticity_hicks_w income_elasticity_w, ///
    by(income_class) statistics(mean sd min max) columns(statistics)
restore
*******************************************************
*  CREATE ELASTICITIES FOR TEMPERATURE AND SEASON
*******************************************************
* --- Temperature Elasticity (marginal effect) ---
gen temp_elasticity = ( _b[temp_centered] + 2*_b[temp_sq_centered]*temp_centered ) * temp_centered / elec_kwh
* --- Dry Season Elasticity (binary variable, % change) ---
gen dryseason_elasticity = (_b[dry_season] / elec_kwh) * 100
* --- Trung bình theo vùng ---
preserve
collapse (mean) temp_elasticity dryseason_elasticity, by(region)
tabstat temp_elasticity dryseason_elasticity, by(region) statistics(mean sd min max)
restore
* --- Trung bình theo nhóm thu nhập ---
preserve
collapse (mean) temp_elasticity dryseason_elasticity, by(income_class)
tabstat temp_elasticity dryseason_elasticity, by(income_class) statistics(mean sd min max)
restore

* tính độ co giãn: Own-price elasticity – Độ co giãn theo giá của điện; Cross-price elasticity – Tác động gián tiếp qua ln_x_P và ln_x_P_sq ; Expenditure elasticity – Độ co giãn theo tổng chi tiêu/thu nhập:

*******************************************************
* QAIDS - TÍNH TOÁN ELASTICITY CHUẨN
*******************************************************

* 1. Chạy mô hình QAIDS (SUR) tối ưu
sureg (w_elec = ln_P ln_x_P ln_x_P_sq tou_urban temp_centered temp_sq_centered ///
       ln_income urban dry_season i.region i.income_class) [aweight=wt9], isure

*******************************************************
* 2. Lấy hệ số γ_ii, β_i, λ_i từ SUR
*******************************************************
scalar gamma = _b[ln_P]       // γ_ii (own-price coefficient)
scalar beta  = _b[ln_x_P]     // β_i (expenditure coefficient)
scalar lambda = _b[ln_x_P_sq] // λ_i (quadratic expenditure coefficient)

display "Gamma (price coefficient) = " gamma
display "Beta (expenditure coefficient) = " beta
display "Lambda (quadratic coefficient) = " lambda

*******************************************************
* 3. Lấy giá trị trung bình
*******************************************************
summarize w_elec
scalar mean_w = r(mean)

summarize ln_x_P
scalar mean_lnx = r(mean)

display "Mean budget share w_elec = " mean_w
display "Mean ln(x/P) = " mean_lnx

*******************************************************
* 4. Tính toán elasticity theo QAIDS (công thức chuẩn)
*******************************************************

* (1) Expenditure elasticity
scalar eta_exp = 1 + (beta + 2*lambda*mean_lnx)/mean_w

* (2) Marshallian (uncompensated) own-price elasticity
scalar eta_marshall = (gamma + 2*lambda*mean_lnx)/mean_w - 1

* (3) Hicksian (compensated) own-price elasticity
scalar eta_hicks = eta_marshall + mean_w*eta_exp

*******************************************************
* 5. Hiển thị kết quả cuối
*******************************************************
display "-------------------------------------------"
display " EXPENDITURE ELASTICITY (QAIDS) = " eta_exp
display " MARSHALLIAN OWN-PRICE ELASTICITY = " eta_marshall
display " HICKSIAN OWN-PRICE ELASTICITY    = " eta_hicks
display "-------------------------------------------"

*******************************************************
* 6. VẼ HISTOGRAM PHÂN PHỐI ELASTICITIES
*******************************************************
histogram price_elasticity_marshall_w, percent normal title("Marshallian Price Elasticity")

histogram price_elasticity_hicks_w,   percent normal title("Hicksian Price Elasticity")

histogram income_elasticity_w,        percent normal title("Income Elasticity")

*******************************************************
* TÍNH VÀ TỔNG HỢP HỆ SỐ CO GIÃN THEO VÙNG (QAIDS)
*******************************************************

* Bước 1: Lưu dữ liệu gốc
preserve

* Bước 2: Tạo bảng tạm để lưu kết quả
tempfile elasticity_by_region
clear
set obs 1
gen byte region_code = .
gen str30 region_name = ""
gen double eta_exp = .
gen double eta_marshall = .
gen double eta_hicks = .
drop if missing(region_code)
save `elasticity_by_region', replace

* Bước 3: Quay lại dữ liệu gốc
restore

* Bước 4: Lặp qua từng vùng
levelsof region, local(regions)
foreach r of local regions {
    preserve
    keep if region == `r'
    
    * Gán nhãn vùng nếu có
    local region_label : label (region) `r'
    
    * Chạy mô hình QAIDS
    quietly sureg (w_elec = ln_P ln_x_P ln_x_P_sq tou_urban temp_centered temp_sq_centered ///
                   ln_income urban dry_season i.income_class) [aweight=wt9], isure
    
    * Lấy hệ số
    scalar gamma = _b[ln_P]
    scalar beta  = _b[ln_x_P]
    scalar lambda = _b[ln_x_P_sq]
    
    quietly summarize w_elec
    scalar mean_w = r(mean)
    quietly summarize ln_x_P
    scalar mean_lnx = r(mean)
    
    scalar eta_exp = 1 + (beta + 2*lambda*mean_lnx)/mean_w
    scalar eta_marshall = (gamma + 2*lambda*mean_lnx)/mean_w - 1
    scalar eta_hicks = eta_marshall + mean_w * eta_exp

    * Ghi kết quả vào bảng tạm
    clear
    set obs 1
    gen byte region_code = `r'
    gen str30 region_name = "`region_label'"
    gen double eta_exp = eta_exp
    gen double eta_marshall = eta_marshall
    gen double eta_hicks = eta_hicks

    append using `elasticity_by_region'
    save `elasticity_by_region', replace
    restore
}

* Bước 5: Hiển thị bảng kết quả
use `elasticity_by_region', clear
sort region_code
list region_code region_name eta_exp eta_marshall eta_hicks, noobs sepby(region_code)

*******************************************************
* TÍNH VÀ TỔNG HỢP HỆ SỐ CO GIÃN THEO NHÓM THU NHẬP (QAIDS)
*******************************************************

* Bước 1: Lưu dữ liệu gốc
preserve

* Bước 2: Tạo bảng tạm để lưu kết quả
tempfile elasticity_by_income
clear
set obs 1
gen byte income_code = .
gen str30 income_label = ""
gen double eta_exp = .
gen double eta_marshall = .
gen double eta_hicks = .
drop if missing(income_code)
save `elasticity_by_income', replace

* Bước 3: Quay lại dữ liệu gốc
restore

* Bước 4: Lặp qua từng nhóm thu nhập
levelsof income_class, local(classes)
foreach c of local classes {
    preserve
    keep if income_class == `c'
    
    * Lấy nhãn thu nhập nếu có
    local label : label (income_class) `c'
    
    * Chạy mô hình QAIDS
    quietly sureg (w_elec = ln_P ln_x_P ln_x_P_sq tou_urban temp_centered temp_sq_centered ///
                   ln_income urban dry_season i.region) [aweight=wt9], isure
    
    * Lấy hệ số
    scalar gamma = _b[ln_P]
    scalar beta  = _b[ln_x_P]
    scalar lambda = _b[ln_x_P_sq]
    
    quietly summarize w_elec
    scalar mean_w = r(mean)
    quietly summarize ln_x_P
    scalar mean_lnx = r(mean)
    
    scalar eta_exp = 1 + (beta + 2*lambda*mean_lnx)/mean_w
    scalar eta_marshall = (gamma + 2*lambda*mean_lnx)/mean_w - 1
    scalar eta_hicks = eta_marshall + mean_w * eta_exp

    * Ghi kết quả vào bảng tạm
    clear
    set obs 1
    gen byte income_code = `c'
    gen str30 income_label = "`label'"
    gen double eta_exp = eta_exp
    gen double eta_marshall = eta_marshall
    gen double eta_hicks = eta_hicks

    append using `elasticity_by_income'
    save `elasticity_by_income', replace
    restore
}

* Bước 5: Hiển thị bảng kết quả
use `elasticity_by_income', clear
sort income_code
list income_code income_label eta_exp eta_marshall eta_hicks, noobs

graph bar eta_hicks, over(income_label, label(angle(45) labsize(small))) ///
    bar(1, color(navy)) ///
    title("Hicksian Own-Price Elasticity by Income Group") ///
    ytitle("Elasticity") ///
    blabel(bar, format(%6.2f)) ///
    legend(off)

graph bar eta_exp, over(income_label, label(angle(45) labsize(small))) ///
    bar(1, color(forest_green)) ///
    title("Expenditure Elasticity by Income Group") ///
    ytitle("Elasticity") ///
    blabel(bar, format(%6.2f)) ///
    legend(off)
*******************************************************
* 4. ELASTICITIES BY INCOME QUINTILE
*******************************************************
twoway ///
    (line price_elasticity income_group, lcolor(blue) lwidth(medthick) ///
         msymbol(circle) mcolor(blue)) ///
    (line hicksian_elasticity income_group, lcolor(red) lwidth(medthick) ///
         msymbol(square) mcolor(red)), ///
    legend(order(1 "Marshallian" 2 "Hicksian") ///
           ring(0) position(11)) ///
    xtitle("Income Quintile") ///
    ytitle("Price Elasticity") ///
    xlabel(1 "Q1" 2 "Q2" 3 "Q3" 4 "Q4" 5 "Q5") ///
    title("Price Elasticities by Income Quintile", size(medium))

graph export "elasticities_by_quintile.png", replace width(800) height(600)

* ĐỒ THỊ 3: Độ co giãn thu nhập theo nhóm thu nhập
twoway ///
    (line price_elasticity income_quintile, lwidth(medthick) lcolor(blue) ///
         msymbol(circle) mcolor(blue) ///
         ytitle("Elasticity") ///
         xtitle("Income Quintile") ///
         ylabel(-1(0.2)1) ///
         xlabel(1 "Q1" 2 "Q2" 3 "Q3" 4 "Q4" 5 "Q5") ///
    ) ///
    (line income_elasticity income_quintile, lwidth(medthick) lcolor(red) ///
         msymbol(square) mcolor(red)) ///
    , ///
    legend(order(1 "Price Elasticity" 2 "Income Elasticity") ///
           ring(0) position(11)) ///
    title("Price and Income Elasticities by Income Quintile", ///
          size(medium))

histogram w_elec, normal
kdensity w_elec
*******************************************************
* COMPENSATING VARIATION (CV)
*******************************************************
summarize w_elec TONGCHITIEU_monthly_VND

* Giá điện trước và sau theo Quyết định 599
scalar P0 = 2114.86
scalar P1 = 2204.07
scalar delta_p = (P1 - P0) / P0

* Tính CV theo công thức QAIDS
scalar CV = mean_w * TONGCHITIEU_monthly_VND * delta_p * eta_hicks

*******************************************************
* 6. Hiển thị kết quả cuối
*******************************************************
display "-------------------------------------------"
display " EXPENDITURE ELASTICITY (QAIDS) = " eta_exp
display " MARSHALLIAN OWN-PRICE ELASTICITY = " eta_marshall
display " HICKSIAN OWN-PRICE ELASTICITY    = " eta_hicks
display " COMPENSATING VARIATION (CV)      = " CV
display "-------------------------------------------"

*******************************************************
* 1. Giả định tăng giá điện TOU (ví dụ: 10%)
*******************************************************
* delta_p_peak là mức tăng giá theo tỷ lệ (10% = 0.10)
gen delta_p_peak = 0.10
*******************************************************
* 2. Tính Compensating Variation (CV) cho từng hộ
*******************************************************
* CV biểu thị số tiền cần bù để hộ dân đạt lại mức tiện ích ban đầu khi giá điện tăng
* Công thức (gần đúng từ Taylor expansion 1st-order + own-price elasticity):
* CV ≈ Q_elec * ΔP * (1 + 0.5 * HES)
gen cv = elec_kwh * delta_p_peak * (1 + eta_hicks/2)

* Áp trọng số khảo sát
gen cv_w = cv * wt9

*******************************************************
* 3. Tổng hợp CV và độ co giãn theo nhóm thu nhập và khu vực
*******************************************************
preserve 
collapse (mean) eta_hicks income_elasticity price_elasticity cv cv_w, ///
    by(income_group urban)
* Hiển thị kết quả trung bình
list income_group urban eta_hicks income_elasticity price_elasticity cv cv_w, sepby(income_group)
restore    
*******************************************************
* 4. Minh họa CV theo thu nhập và khu vực bằng biểu đồ cột
*******************************************************
graph bar cv, over(urban, label(labsize(medium))) ///
    over(income_group, label(labsize(medium) valuelabel)) ///
    ascategory ///
    legend(order(1 "Rural" 2 "Urban")) ///
    ytitle("Compensating Variation (VND/month)") ///
    title("Compensating Variation by Income Quintile and Urban/Rural")


*******************************************************
* 5. COMPENSATING VARIATION BY INCOME & AREA
*******************************************************
graph bar cv, over(urban, label(labsize(medium))) ///
    over(income_group, label(labsize(medium) valuelabel)) ///
    ascategory ///
    legend(order(1 "Rural" 2 "Urban")) ///
    ytitle("Compensating Variation (VND/month)") ///
    title("Compensating Variation by Income Quintile and Urban/Rural")

*******************************************************
* 11. VẼ SCATTER FIRST-STAGE ln_price_mp vs ln_avg_price_excl_mp
*******************************************************
* Mục đích: Kiểm tra tính liên quan (relevance) của biến công cụ ln_avg_price_excl_mp
* với biến nội sinh ln_price_mp trong mô hình 2SLS

twoway ///
    (scatter ln_price_mp ln_avg_price_excl_mp, mcolor(blue%70) msize(small) ///
        legend(label(1 "Observed Data"))) ///
    (lfit ln_price_mp ln_avg_price_excl_mp, lcolor(red) lwidth(medthick) ///
        legend(label(2 "Fitted Line"))), ///
    title("First-stage Relationship: ln_price_mp vs ln_avg_price_excl_mp", size(medium)) ///
    xtitle("Instrument: Regional Average Electricity Price (ln_avg_price_excl_mp)") ///
    ytitle("Household Electricity Price (ln_price_mp)") ///
    legend(order(1 2) region(lcolor(white))) ///
    note("Positive correlation confirms instrument relevance for 2SLS estimation.") ///
    xlabel(, grid) ylabel(, grid)

*******************************************************
* 12. LƯU KẾT QUẢ RA BẢNG SO SÁNH
*******************************************************
esttab ols_model iv_model qaids_model using "Results_OLS_IV_QAIDS.rtf", ///
    replace se r2 ar2 label
	
* Hiển thị bảng so sánh kết quả ngay trong Stata
esttab ols_model iv_model qaids_model, ///
    se r2 ar2 label ///
    title("Comparison of OLS, IV, and QAIDS Models")

*******************************************************	
* 9. ĐỒ THỊ MINH HỌA 
*******************************************************

* ĐỒ THỊ 1: Histogram – Monthly Electricity Consumption (kWh/tháng)
histogram elec_kwh, frequency normal ///
    title("Distribution of Monthly Electricity Consumption (kWh)") ///
    xtitle("kWh per Month") ytitle("Number of Households") ///
    color(blue%50) lcolor(black)
graph export "fig1_distribution.png", replace width(800) height(600)

* ĐỒ THỊ 2: Mối quan hệ giá - lượng (scatter + fitted)
* Scatter + Fitted line (Log-Log) theo giá trung bình:
twoway (scatter ln_kwh ln_price_ap, mcolor(blue%30)) ///
       (lfit ln_kwh ln_price_ap, lcolor(red) lwidth(thick)), ///
       title("Price-Quantity Relationship (Average Price, Log-Log)") ///
       xtitle("Log(Average Price per kWh)") ytitle("Log(Electricity Consumption)") ///
       legend(label(1 "Observed") label(2 "Fitted Line"))
graph export "fig_price_quantity_ap.png", replace width(800) height(600)

* Scatter + Fitted line (Log-Log) theo giá trung bình
twoway (scatter ln_kwh ln_price_mp, mcolor(blue%30)) ///
       (lfit ln_kwh ln_price_mp, lcolor(red) lwidth(thick)), ///
       title("Price-Quantity Relationship (Marginal Price, Log-Log)") ///
       xtitle("Log(Marginal Price per kWh)") ytitle("Log(Electricity Consumption)") ///
       legend(label(1 "Observed") label(2 "Fitted Line"))
graph export "fig_price_quantity_mp.png", replace width(800) height(600)
		  
* đồ thị 4: Biến đổi Bù trừ (CV) theo nhóm thu nhập và khu vực thành thị/nông thôn.

graph bar cv, over(urban, ///
        label(labsize(medium))) ///
    over(income_quintile, ///
        label(labsize(medium) valuelabel)) ///
    ascategory ///
    legend(order(1 "Rural" 2 "Urban")) ///
    ytitle("Compensating Variation (VND/month)") ///
    xtitle("Income Quintile") ///
    title("Compensating Variation by Income Quintile and Urban/Rural")

* ĐỒ THỊ 4: Tác động TOU theo khu vực
gen tou_impact = 0.31 * (0.4 - tou_ratio)
twoway (histogram tou_impact if urban == 1, frequency color(blue%50) lcolor(black)) ///
       (histogram tou_impact if urban == 0, frequency color(red%50) lcolor(black)), ///
       title("TOU Impact on Expenditure Share by Area") ///
       xtitle("Change in Electricity Share (%)") ytitle("Density") ///
       legend(label(1 "Urban") label(2 "Rural"))
graph export "fig4_tou_impact.png", replace width(800) height(600)

*******************************************************
* 12. XUẤT BẢNG TỔNG HỢP
*******************************************************
esttab m2sls_full qaids_full using "final_results.rtf", ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    title("Table 1: Estimation Results") ///
    mtitles("2SLS" "QAIDS") replace

esttab m2sls_full qaids_full using "Model_Summary_All.rtf", ///
    se star(* 0.10 ** 0.05 *** 0.01) replace ///
    label title("Summary Diagnostics: 2SLS & QAIDS")
	
*******************************************************
* 5. WELFARE & SIMULATION
* Compensating Variation (Bockstael & McConnell, 2007)
* CV = Q * ΔP * (1 + ε / 2)
* ε dùng: Price elasticity under TOU × Urban
*******************************************************
*******************************************************
* 1. CREATE INCOME DECILES
*******************************************************
xtile income_decile = TONGTHU_monthly_VND, n(10)
label variable income_decile "Income Decile (1=Poorest, 10=Richest)"

*******************************************************
* 2. DEFINE BEHAVIORAL PARAMETERS
*******************************************************
* 10% TOU peak price increase
gen delta_p_peak = 0.10
label variable delta_p_peak "Peak-hour Price Increase (10%)"

* Price elasticity (elasticity under TOU × Urban)
* 0.31 là hệ số ước lượng của biến tương tác TOU × Urban
gen price_elasticity = 0.31 * tou_urban
label variable price_elasticity "Price Elasticity (TOU × Urban)"

*******************************************************
* 3. CURRENT WELFARE LOSS (Compensating Variation)
* CV = Q * ΔP * (1 + ε / 2)
*******************************************************
gen cv_loss = elec_kwh * delta_p_peak * (1 + price_elasticity/2)
label variable cv_loss "Welfare Loss (CV, monthly)"

*******************************************************
* 4. WEIGHTED CV (VHLSS Sampling Weights)
*******************************************************
gen cv_loss_w = cv_loss * wt9
label variable cv_loss_w "Weighted CV (VND, monthly)"

*******************************************************
* 5. Summary Statistics by Income Decile and Urban/Rural
*******************************************************
bysort income_decile urban: egen cv_mean = mean(cv_loss)
label variable cv_mean "Mean CV by Decile × Urban"

bysort income_decile urban: egen cvw_mean = mean(cv_loss_w)
label variable cvw_mean "Weighted Mean CV by Decile × Urban"

* Mean, SD, Min, Max of CV (monthly, weighted and unweighted)
* Theo income decile
tabstat cv_loss cv_loss_w, by(income_decile) statistics(mean sd min max) columns(statistics)

* Theo urban/rural
tabstat cv_loss cv_loss_w, by(urban) statistics(mean sd min max) columns(statistics)

* Chú thích:
* cv_loss      : CV without weights
* cv_loss_w    : CV weighted by VHLSS sample weight (wt9)
* income_decile: 1=Poorest, 10=Richest
* urban        : 0=Rural, 1=Urban

*******************************************************
* 4. MÔ PHỎNG NĂM 2030 (Future Scenario)
*******************************************************
*******************************************************
* FUTURE SCENARIO 2030: CV SIMULATION
*******************************************************
* Assumptions:
* - Income grows 6% per year
* - Electricity price increases 5% per year
* - 8 years from current period

* Project income and electricity price for 2030
gen income_2030 = TONGTHU_monthly_VND * (1.06^8)
gen price_2030  = p_elec * (1.05^8)

* Compute CV for 2030 (unweighted and weighted)
* Using formula: CV ≈ Q * P * (1 + ε/2)
gen cv_2030   = elec_kwh * price_2030 * (1 + 0.31/2)
gen cv_2030_w = cv_2030 * wt9

* Optional: create decile × urban variable for grouping
gen decile_urban = income_decile*10 + urban
label define decile_urban_lbl ///
    11 "Decile1-Rural" 12 "Decile1-Urban" ///
    21 "Decile2-Rural" 22 "Decile2-Urban" ///
    31 "Decile3-Rural" 32 "Decile3-Urban" ///
    41 "Decile4-Rural" 42 "Decile4-Urban" ///
    51 "Decile5-Rural" 52 "Decile5-Urban" ///
    61 "Decile6-Rural" 62 "Decile6-Urban" ///
    71 "Decile7-Rural" 72 "Decile7-Urban" ///
    81 "Decile8-Rural" 82 "Decile8-Urban" ///
    91 "Decile9-Rural" 92 "Decile9-Urban" ///
    101 "Decile10-Rural" 102 "Decile10-Urban"
label values decile_urban decile_urban_lbl

* Tabstat summary by decile × urban
tabstat cv_2030 cv_2030_w, by(decile_urban) statistics(mean sd min max) columns(statistics)

*******************************************************
* 5. CO₂ SAVINGS CALCULATION
*******************************************************
*******************************************************
* Create peak reduction variable
*******************************************************
gen peak_reduction = 0.31 * tou_urban   // 0.31 = assumed elasticity for peak reduction
label variable peak_reduction "Peak consumption reduction factor (TOU × Urban)"
* Assumption: emission factor = 0.45 kg CO₂ per kWh

gen co2_saving_kg   = peak_reduction * elec_kwh * 12 * 0.45   // annual saving in kg
gen co2_saving_ton  = co2_saving_kg / 1000                     // convert to tons
gen co2_saving_w    = co2_saving_ton * wt9                     // weighted by survey weight

*******************************************************
* 6. COLLAPSE RESULTS BY DECILE & URBAN/RURAL
*******************************************************
collapse ///
    (mean) cv_current  = cv_loss_w  /// weighted current CV
    (mean) cv_future   = cv_2030_w  /// weighted future CV
    (mean) co2_saving  = co2_saving_w, ///
    by(income_decile tou_urban)

* Label variables for clarity
label variable cv_current "Current Compensating Variation (VND/month)"
label variable cv_future  "Future Compensating Variation (2030, VND/month)"
label variable co2_saving "Annual CO₂ Savings (tons, weighted)"

* Optional: display table
list, sepby(income_decile) noobs

*******************************************************
* 7. KIỂM TRA KẾT QUẢ
*******************************************************
list income_decile tou_urban cv_current cv_future co2_saving, sepby(income_decile)
*******************************************************
*******************************************************
* 8. XUẤT RA EXCEL
*******************************************************
export excel income_decile tou_urban cv_current cv_future co2_saving ///
    using "welfare_cv_co2_summary.xlsx", ///
    firstrow(variables) replace sheet("Summary")

*******************************************************
* 13. KẾT THÚC
*******************************************************
log close
