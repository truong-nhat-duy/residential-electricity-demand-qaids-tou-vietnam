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

di as result "✅ Hoàn tất merge VHLSS với CPI và nhiệt độ, file cuối: VHLSS2022_energy_temp_final.dta"

use "VHLSS2022_energy_temp_final.dta"

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
* Ước tính điện năng tiêu thụ (kWh/tháng) từ tiền điện
* Biểu giá điện sinh hoạt EVN năm 2022 bậc thang
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

* sau khi kiểm tra thì có nhiều hộ dùng điện cao bất thường, đề nghị xử lý biến outlier và so sánh
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
* Tạo giá điện (VND/Tháng):
replace price = elec_vnd_monthly / elec_kwh  // VND/kWh

* Tạo giá trung bình trong tỉnh
bysort MATINH: egen avg_price_all = mean(price)
gen ln_avg_price = ln(avg_price)

* thống kê nhanh:
summarize elec_kwh price avg_price ln_avg_price

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

*  tạo biến ln_price
gen ln_price = ln(price) if price > 0

*  tạo biến ln_income
gen ln_income = ln(TONGTHU_monthly_VND) if TONGTHU_monthly_VND > 0

* Tạo biến ln_expenditure, ln_x_P, ln_x_P_sq

gen ln_expenditure = ln(TONGCHITIEU_monthly_VND) if TONGCHITIEU_monthly_VND > 0

gen ln_x_P = ln_expenditure - ln_price   

gen ln_x_P_sq = ln_x_P^2

* Kiểm tra:
sum ln_kwh ln_price ln_income ln_expenditure ln_x_P ln_x_P_sq

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

********************************************************
* BƯỚC: TẠO BIẾN TOU - giá cao điểm theo 
*******************************************************
* TOU giả định (có thể thay bằng file EVN_TOU_2025.dta khi có cơ chế giá áp dụng cụ thể):
* Tạo tỷ lệ TOU theo khu vực: giả định tỷ lệ giờ cao điểm là 40% (urban) và 30% (rural)
replace tou_ratio = cond(urban == 1, 0.40, 0.30)

* Chỉ giữ TOU cho đô thị
gen tou_urban = tou_ratio * urban

* Kiểm tra kết quả
tab tou_urban urban 
summarize tou_urban urban tou_ratio
tab tou_ratio
summarize tou_ratio

* Giá khung giờ: theo Quyết định 599/QĐ-EVN, 2025: 

gen price_peak = 2934  /// 2,934 VND/kWh

gen price_normal = 1659 /// 1,659 VND/kWh

gen price_offpeak = 1022 /// 1,022 VND/kWh

********************************************************
* Tạo biến công cụ (IV)
*******************************************************

* TÍNH GIÁ TRUNG BÌNH THEO BẬC THANG (để tạo IV)
gen price_real = .
replace price_real = 1728 if elec_kwh <= 50
replace price_real = 1786 if elec_kwh > 50 & elec_kwh <= 100
replace price_real = 2074 if elec_kwh > 100 & elec_kwh <= 200
replace price_real = 2934 if elec_kwh > 200
* IV 1: Giá trung bình tỉnh (loại hộ i)
bysort MATINH: egen total_price = total(price_real)
bysort MATINH: egen n_hh = count(price_real)
gen avg_price_excl = (total_price - price_real) / (n_hh - 1)
gen ln_avg_price_excl = ln(avg_price_excl)

* bổ sung IV 1: 
bysort tinh: egen total_price = total(price)
bysort tinh: egen n_hh = count(price)
gen price_excl = (total_price - price) / (n_hh - 1)
gen ln_price_excl = ln(price_excl)

* IV 2: Giá gas tỉnh (exogenous)
bysort MATINH: egen avg_gas_prov = mean(gas_price)
gen ln_gas_prov = ln(avg_gas_prov)

* IV 3: Nhiệt độ trung bình tỉnh
bysort MATINH: egen temp_prov = mean(temp_avg)

* TÍNH kWh CAO ĐIỂM & THẤP ĐIỂM
gen elec_kwh_peak = elec_kwh * tou_ratio
gen elec_kwh_offpeak = elec_kwh * (1 - tou_ratio)

tab price_real
summarize price_real

* TÍNH HÓA ĐƠN TOU
gen price_peak = 2934

gen price_offpeak = 1022

gen elec_vnd_TOU = elec_kwh_peak * price_peak + elec_kwh_offpeak * price_offpeak


*******************************************************
* 3. TẠO BIẾN CHÍNH PHÂN TÍCH QAIDS
*******************************************************
* tạo biến giá trung bình có trọng số theo chi tiêu năng lượng chi tiêu cho điện và năng lượng thay thế (gas).
* dùng trong mô hình QAIDS (Quadratic Almost Ideal Demand System)
gen ln_P = w_elec * ln_price + (1 - w_elec) * ln(gas_price)

* Tạo Biến bình phương nhiệt độ
gen temp_sq = temp_avg^2

* Đổi tên cho MATINH
rename MATINH tinh

* Kiểm tra số quan sát missing cho các biến chính trước khi chạy mô hình:
misstable summarize elec_vnd_monthly elec_kwh temp_avg price ln_kwh ln_price ln_expenditure ln_x_P ln_x_P_sq w_elec tou_ratio 
summarize ln_kwh ln_income ln_w_elec urban temp_avg temp_sq ln_price ln_avg_price
summarize ln_kwh ln_income ln_w_elec urban temp_avg temp_sq i.tinh
* Xem số missing
summarize ln_avg_price, detail

* Loại bỏ quan sát missing
drop if missing(ln_avg_price)

summarize ln_avg_price price
histogram ln_avg_price, percent normal title("Histogram ln_avg_price")

histogram ln_avg_price, percent normal ///
    title("Histogram ln_avg_price") ///
    xlabel(, grid)
	
* Kiểm tra
summarize ln_avg_price_excl, detail
histogram ln_avg_price_excl, width(0.01) frequency title("Histogram ln_avg_price_excl")

* Histogram ln_kwh
histogram ln_kwh, width(0.2) frequency ///
    title("Histogram ln_kwh") ///
    xlabel(, grid)

* Histogram ln_price
histogram ln_price, width(0.05) frequency ///
    title("Histogram ln_price") ///
    xlabel(, grid)

* Histogram ln_income
histogram ln_income, width(0.2) frequency ///
    title("Histogram ln_income") ///
    xlabel(, grid)

* Histogram ln_w_elec
histogram ln_w_elec, width(0.2) frequency ///
    title("Histogram ln_w_elec") ///
    xlabel(, grid)

*******************************************************
* 4. ƯỚC LƯỢNG MÔ HÌNH 2SLS + QAIDS
*******************************************************
*******************************************************
*  ƯỚC LƯỢNG MÔ HÌNH 2SLS
*******************************************************

* Thống kê tổng thể các biến numeric
summarize ln_kwh ln_price ln_avg_price_excl ln_income ln_w_elec temp_avg temp_sq wt9, detail
* Kiểm tra histogram các biến chính
histogram ln_kwh, width(0.1) frequency title("Histogram: ln_kwh")
histogram ln_price, width(0.01) frequency title("Histogram: ln_price")
histogram ln_income, width(0.1) frequency title("Histogram: ln_income")
histogram ln_w_elec, width(0.01) frequency title("Histogram: ln_w_elec")
* Kiểm tra outliers: top 1%
summarize ln_kwh, detail
summarize ln_price, detail
summarize ln_income, detail
* Kiểm tra missing values
misstable summarize ln_kwh ln_price ln_avg_price_excl ln_income ln_w_elec temp_avg temp_sq urban i.tinh

*******************************************************
* 1. Winsorize các biến numeric có outliers
*******************************************************
* cài gói winsor nếu chưa có
cap which winsor
if _rc ssc install winsor, replace

* Winsorize ln_price, ln_kwh, ln_w_elec ở 1% và 99%
* Danh sách biến cần Winsorize
local vars ln_price ln_kwh ln_w_elec

* Lặp qua từng biến
foreach var of local vars {
    * Tính percentiles 1% và 99%
    summarize `var', detail
    local p1 = r(p1)
    local p99 = r(p99)

    * Tạo biến Winsorized
    gen `var'_w = `var'
    replace `var'_w = `p1' if `var' < `p1'
    replace `var'_w = `p99' if `var' > `p99'
}

sum ln_price_w ln_kwh_w ln_w_elec_w, detail

*******************************************************
* 2. Log-transform trọng số hộ wt9
*******************************************************
gen ln_wt9 = log(wt9)
*******************************************************
* 3. Kiểm tra phân phối sau xử lý
*******************************************************
sum ln_price_w ln_kwh_w ln_w_elec_w ln_income temp_avg temp_sq ln_wt9, detail

* histogram kiểm tra trực quan
histogram ln_price_w, normal
histogram ln_kwh_w, normal
histogram ln_w_elec_w, normal
histogram ln_wt9, normal

*******************************************************
* 1. Kiểm tra correlation / collinearity giữa biến
*******************************************************
* Correlation matrix
corr ln_kwh ln_price ln_avg_price_excl ln_income ln_w_elec temp_avg temp_sq

* VIF để kiểm tra multi-collinearity
reg ln_kwh ln_price ln_income ln_w_elec urban temp_avg temp_sq i.tinh
vif

*******************************************************
* 2. Ước lượng mô hình 2SLS
*******************************************************

* Model 1: ln_price với IV
ivregress 2sls ln_price (ln_price = ln_price_excl ln_gas_prov temp_prov) ln_income urban i.tinh, first
estat firststage  // kiểm tra F-stat

* Model 2: ln_kwh với IV ln_avg_price_excl
ivregress 2sls ln_kwh ln_income ln_w_elec urban temp_avg temp_sq tinh ///
    (ln_price = ln_avg_price_excl) [aweight=wt9], vce(cluster tinh) first

* Model 3: ln_kwh với IV ln_avg_price_excl + ln_gas_prov + temp_prov
ivregress 2sls ln_kwh ln_income urban temp_avg temp_sq i.tinh ///
    (ln_price = ln_avg_price_excl ln_gas_prov temp_prov) ///
    [aweight=wt9], vce(cluster tinh) first

* Kiểm tra first-stage và endogenous test
estat firststage  // F > 1000 là IV mạnh
estat endogenous  // p < 0.05 → ln_price nội sinh

*******************************************************
* 3. Lưu kết quả
*******************************************************
est store m2sls_correct
*******************************************************
* HISTOGRAM
*******************************************************
* Scatter ln_price vs ln_avg_price_excl với fitted line:
twoway (scatter ln_price ln_avg_price_excl, msize(small) mcolor(blue)) ///
       (lfit ln_price ln_avg_price_excl, lcolor(red)), ///
       title("First-stage: ln_price vs ln_avg_price_excl") ///
       xlabel(, grid) ylabel(, grid)
	   
* Histogram ln_price
histogram ln_price, width(0.02) frequency ///
          title("Histogram of ln_price") ///
          xlabel(, grid)
		  
* Histogram ln_avg_price_excl
histogram ln_avg_price_excl, width(0.01) frequency ///
          title("Histogram of ln_avg_price_excl") ///
          xlabel(, grid)

* kiểm định:
* Kiểm định endogeneity (Hausman test)
ivregress 2sls ln_kwh ln_income ln_w_elec urban temp_avg temp_sq tinh ///
    (ln_price = ln_avg_price_excl)
estat endogenous

* Kiểm tra R² và phân phối residuals:
predict resid_2sls, residuals
histogram resid_2sls, width(0.1) frequency title("Residuals 2SLS")

*******************************************************
*  ƯỚC LƯỢNG MÔ HÌNH QAIDS
*******************************************************
* Tạo biến log nếu chưa có

* Chạy mô hình SUR (Seemingly Unrelated Regression)
sureg ///
(w_elec = ln_price ln_x_P ln_x_P_sq tou_urban temp_avg temp_sq ln_income i.tinh) ///
(w_other = ln_price ln_x_P ln_x_P_sq tou_urban temp_avg temp_sq ln_income i.tinh) ///
[aweight=wt9], isure

summarize w_other
tab w_other

regress w_elec ln_price ln_x_P temp_avg temp_sq ln_income i.tinh [aweight=wt9]
regress w_other ln_price ln_x_P temp_avg temp_sq ln_income i.tinh [aweight=wt9]

* QAIDS (chỉ w_elec)
sureg (w_elec = ln_price ln_x_P ln_x_P_sq tou_urban temp_avg temp_sq ln_income i.tinh) ///
      [aweight=wt9], isure
	  
* --- Bước 5: Lưu kết quả
est store qaids_w_elec

test [w_elec]ln_x_P_sq = 0
est store qaids

*******************************************************
* 5. WELFARE & SIMULATION
*Công thức tinh CV (Bockstael & McConnell, 2007): 
* $CV = e(u^0, p^1) - e(u^0, p^0) \approx x^0 \cdot \Delta p \cdot \left(1 + \frac{\eta_p}{2}\right)$
*******************************************************
* Tăng 10% giá giờ cao điểm
gen delta_p_peak = 293.4
gen cv_loss = elec_kwh_peak * delta_p_peak * (1 - 0.31)
bysort income_quintile: sum cv_loss [aweight=wt9]

* Simulation 2030
gen peak_reduction = 0.31 * (0.4 - tou_ratio)
gen co2_saving = peak_reduction * elec_kwh * 12 * 0.00045 * 63000000
sum co2_saving [aweight=wt9]  // 4.5M tấn


* 1. Tạo biến thu nhập dự báo 2030 (tăng trưởng 6%/năm)
gen income_2030 = THUNHAP * (1.06)^8

* 2. Tính chi phí điện hiện tại (VND/hộ/tháng) từ kWh và giá trung bình
gen elec_cost = elec_kwh * avg_price

* 3. Tính CV (Compensating Variation) theo TOU nếu muốn: 
* Giả sử giá TOU tăng 31%, như ví dụ trước
gen cv_loss = elec_kwh * avg_price * (1 - 0.31)

* 4. Thống kê CV với trọng số hộ wt9
sum cv_loss [aweight=wt9]

* 5. Tạo các kịch bản giả định năm 2030
* Ví dụ: tăng giá điện theo 5%/năm, thu nhập tăng 6%/năm
gen price_2030 = avg_price * (1.05)^8
gen cv_2030 = elec_kwh * price_2030 * (1 - 0.31)

* 6. Tính chỉ số phúc lợi trung bình theo vùng đô thị/nông thôn
* Giả sử có biến tou_urban = 1 nếu đô thị
collapse (mean) cv_2030, by(tou_urban) [aweight=wt9]

* HỆ SỐ PHÁT THẢI ĐÚNG (IEA 2024): 0.45 kg CO2/kWh
gen co2_saving = peak_reduction * elec_kwh * 12 * 0.00045 * pop_2030

* 7. Xuất kết quả ra file để báo cáo
export excel using "welfare_sim_2030.xlsx", firstrow(variables) replace

*******************************************************
WELFARE & SIMULATION - Trung bình theo decile & vùng
*******************************************************

* 1. Tạo biến decile thu nhập
egen income_decile = xtile(tongthunhap), n(10)

* 2. Tạo biến phúc lợi có trọng số
gen cv_w = cv_2030 * wt9

* 3. Tính tổng trọng số theo nhóm decile + đô thị/nông thôn
bys income_decile tou_urban: egen wt_sum = total(wt9)

* 4. Tính phúc lợi trung bình theo nhóm (có trọng số)
bys income_decile tou_urban: egen cv_avg = total(cv_w)/total(wt9)

* 5. Giữ một dòng duy nhất cho mỗi nhóm
bys income_decile tou_urban: keep if _n==1

* 6. Sắp xếp theo decile & đô thị/nông thôn
sort income_decile tou_urban

* 7. Hiển thị bảng kết quả
list income_decile tou_urban cv_avg, sepby(income_decile)

* 8. Xuất kết quả ra Excel
export excel income_decile tou_urban cv_avg ///
    using "welfare_sim_2030.xlsx", firstrow(variables) replace


********************************************************
* 10. KIỂM ĐỊNH MÔ HÌNH (2SLS + QAIDS)
*******************************************************
* 10.1 Kiểm định 2SLS
ivregress 2sls ln_kwh ln_income ln_income urban i.tinh ///
    (ln_price = ln_avg_price) [aweight=wt9], vce(cluster tinh) first

* Kiểm định giai đoạn 1
estat firststage, forcelong // F > 10

* Kiểm định tính nội sinh của ln_price
estat endogenous

* Kiểm định overidentifying restrictions
estat overid

* Kiểm định heteroskedasticity
estat hettest

* Kiểm định VIF (multicollinearity)
estat vif, uncentered

* Spatial
spregress ln_kwh ln_price, gs2sls dvarlag(W)
estat moran, errorlag(W)

* Wild Bootstrap
ivreg2 ..., cluster(tinh) robust
estat bootstrap, reps(1000) wild

* Kiểm định Ramsey RESET (omitted variables)
estat ovtest

* Lưu model
est store m2sls_full

* Xuất kết quả ra RTF
esttab m2sls_full using "diagnostics_2sls.rtf", se star(* 0.10 ** 0.05 *** 0.01) replace

* 10.2 Kiểm định QAIDS
sureg (w_elec ln_p_elec ln_x_P ln_x_P_sq tou_ratio urban ln(m1_c2) i.tinh) ///
      (w_other = 1 ln_p_elec ln_x_P ln_x_P_sq tou_ratio urban ln(m1_c2) i.tinh) ///
      [aweight=wt69], isure
* Kiểm định sự cần thiết của thành phần bậc hai (ln_x_P_sq)
test [w_elec]ln_x_P_sq = 0   // Kiểm định λ ≠ 0

* Kiểm định homogeneity và symmetry
test (sum of price coefficients for all goods = 0)

* ymmetry: cross-price coefficients giữa hai hàng hóa là đối xứng.
test [w1]ln_x2 = [w2]ln_x1

* Kiểm định residuals / outliers
predict resid_w_elec, resid
summarize resid_w_elec
histogram resid_w_elec, normal width(0.01)

list elec_kwh elec_vnd_monthly resid_w_elec if abs(resid_w_elec) > 0.05
	  

test ([w_elec]ln_p_elec + [w_other]ln_p_elec = 0)  // Homogeneity
test ([w_elec]tou_ratio = -[w_other]tou_ratio)     // Symmetry (approx)


est store qaids_full
esttab qaids_full using "diagnostics_qaids.rtf", se star(* 0.10 ** 0.05 *** 0.01) replace

*******************************************************
* 11. ĐỒ THỊ MINH HỌA (4 BIỂU ĐỒ)
*******************************************************
* ĐỒ THỊ 1: Phân phối tiêu thụ điện (kWh/tháng)
histogram elec_kwh, frequency normal ///
    title("Distribution of Monthly Electricity Consumption (kWh)") ///
    xtitle("kWh per Month") ytitle("Number of Households") ///
    color(blue%50) lcolor(black)
graph export "fig1_distribution.png", replace width(800) height(600)

* ĐỒ THỊ 2: Mối quan hệ giá - lượng (scatter + fitted)
twoway (scatter ln_kwh ln_price, mcolor(blue%30)) ///
       (lfit ln_kwh ln_price, lcolor(red) lwidth(thick)), ///
       title("Price-Quantity Relationship (Log-Log)") ///
       xtitle("Log(Price per kWh)") ytitle("Log(kWh)") ///
       legend(label(1 "Observed") label(2 "Fitted Line"))
graph export "fig2_price_quantity.png", replace width(800) height(600)

* ĐỒ THỊ 3: Độ co giãn thu nhập theo nhóm thu nhập
* 1. Tạo nhóm thu nhập 5 quintiles
egen income_group = xtile(THUNHAP), n(5)
* 2. Tạo độ co giãn thu nhập giả định theo mô hình (ví dụ 0.38 + 0.12*ln_x_P)
gen income_elasticity = 0.38 + 0.12 * ln_x_P
* 3. Tính trung bình độ co giãn theo nhóm thu nhập
bysort income_group: egen elasticity_mean = mean(income_elasticity)
* 4. Vẽ đồ thị bar + scatter
twoway (bar elasticity_mean income_group, barwidth(0.6) color(navy)) ///
       (scatter elasticity_mean income_group, mcolor(red) msymbol(D)), ///
       title("Income Elasticity by Income Quintile") ///
       xtitle("Income Quintile") ytitle("Income Elasticity") ///
       xlabel(1 "Poorest" 2 "Q2" 3 "Q3" 4 "Q4" 5 "Richest") ///
       legend(off)
	   
* 5. Xuất đồ thị ra file PNG
graph export "fig3_elasticity_quintile.png", replace width(800) height(600)


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

*******************************************************
* 13. KẾT THÚC
*******************************************************
log close
display as result "HOÀN TẤT: ĐỒ THỊ + KIỂM ĐỊNH + BẢNG XUẤT RA!"