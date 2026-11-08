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

* === Thiết lập đường dẫn làm việc ===
local dir `c(pwd)'
* === Khởi động log ===
capture log close
log using "QAIDS_TOU_2022.log", replace text

*******************************************************
* 1. NẠP DỮ LIỆU VÀ GHÉP FILE VHLSS 2022
*******************************************************
clear all
cd "D:\01. HOC HANH\13. THAC SI UEH\05. MON HOC\HOC KY 2\03. Phân tích hành vi người tiêu dùng_Mr. Thuy\06. du an cuoi ky\00. FILE LOG-DO-DATABASE"   // 
dir *.dta

*******************************************************
* 2. DANH SÁCH FILE MODULE CẦN GHÉP
*******************************************************
local files B8_Ho_Muc4B22 B9_Ho_Muc4B31 B10_Ho_Muc4B32 B11_Ho_Muc4B41 B12_Ho_Muc4B42 B13_Ho_Muc4B51 B14_Ho_Muc4B52 B15_Ho_Muc4B111A B16_Ho_Muc4B111B
display "`files'"
dir *.dta

*******************************************************
* GHÉP DỮ LIỆU VHLSS 2022
*******************************************************
local firstfile : word 1 of `files'
display "File đầu tiên: `firstfile'"

use "`firstfile'.dta", clear
duplicates drop IDHO, force
tempfile master
save `master', replace

local n : word count `files'
forvalues i = 2/`n' {
    local f : word `i' of `files'
    di "-------------------------------------------------------"
    di as text "🔗 Đang ghép file: `f'.dta"
    
    capture confirm file "`f'.dta"
    if _rc {
        di as error "⚠️ File `f'.dta không tồn tại — bỏ qua!"
        continue
    }

    use "`f'.dta", clear
    
    * Kiểm tra biến định danh
    capture confirm variable IDHO
    if _rc {
        capture confirm variable idho
        if !_rc rename idho IDHO
        else {
            di as error "⚠️ File `f'.dta không có biến IDHO — bỏ qua!"
            continue
        }
    }

    duplicates drop IDHO, force
    sort IDHO
    merge 1:1 IDHO using `master', nogen
    tempfile master
    save `master', replace
}
save "VHLSS2022_merged.dta", replace
display as result "✅ Đã ghép hoàn tất: VHLSS2022_merged.dta"

*******************************************************
* GHÉP NGUỒN CHI TIÊU NĂNG LƯỢNG THEO HỘ GIA ĐÌNH
*******************************************************
* 1️⃣ Mở file năng lượng
use "B15_Ho_Muc4B111A.dta", clear

* 2️⃣ Giữ lại dòng điện sinh hoạt (mã 1)
keep if M4B111A_MA == 1

* 3️⃣ Giữ lại các biến cần thiết
keep IDHO M4B111_C2 M4B111_C5

* 4️⃣ Tạo biến điện tiêu thụ trung bình/tháng
gen electricity_kwh_monthly = M4B111_C2 / 12
gen electricity_spending_monthly = M4B111_C5 / 12

* 5️⃣ Trường hợp có nhiều dòng cho cùng một hộ (hiếm)
collapse (sum) electricity_kwh_monthly electricity_spending_monthly, by(IDHO)

* 6️⃣ Lưu lại
save "electricity_2022.dta", replace

use "VHLSS2022_merged.dta", clear
merge 1:1 IDHO using "electricity_2022.dta"

sum electricity_kwh_monthly electricity_spending_monthly

*******************************************************
* 2. GHÉP NGUỒN NGOÀI (EVN TOU 2025 & CPI GSO)
*******************************************************
* Tải file về thư mục dự án
import delimited "province_energy_panel_2022.csv", clear

* Kiểm tra
list province month gas_price_index gas_price in 1/5

* Lưu .dta để merge với VHLSS
save "province_energy_panel_2022.dta", replace

* 2.1 Ghép bảng giá điện TOU theo tỉnh
merge m:1 tinh using "EVN_TOU_2025.dta"
drop _merge
* -> Biến: peak_price, offpeak_price, tou_ratio (urban: 0.35, rural: 0.15)

* 2.2 Ghép CPI năng lượng GSO
merge m:1 year month using "CPI_energy_2025.dta"
drop _merge
gen real_elec_exp = elec_exp / cpi_energy

*******************************************************
* 3. TẠO BIẾN CHÍNH PHÂN TÍCH QAIDS
*******************************************************

* 3.1 Chuẩn hóa biến năng lượng và thu nhập
gen kwh_percap = kwh / members
gen energy_share = elec_exp / income

* 3.2 Log biến cho QAIDS
gen lny = ln(income)
gen lnp = ln(elec_exp / kwh)

* 3.3 Mô phỏng chính sách TOU (biểu giá theo giờ)
gen adj_cost = (1 + tou_ratio) * real_elec_exp
gen energy_share_tou = adj_cost / income

*******************************************************
* 4. ƯỚC LƯỢNG MÔ HÌNH QAIDS
*******************************************************

* Mô hình QAIDS (Deaton & Muellbauer, 1980)
* w_i = α_i + β_i*ln(y/P) + Σγ_ij*ln(p_j/P) + λ_i*(ln(y/P))^2 + ε_i

* Ví dụ đơn giản cho nhóm năng lượng:
qreg energy_share lny lnp members [aw=weight], quantile(.5)

* hoặc dùng SUR nếu có nhiều nhóm chi tiêu:
* sureg (w_energy = lny lnp members) (w_food = lny lnp members), corr(equations)

*******************************************************
* 5. KIỂM TRA VÀ MÔ PHỎNG TÁC ĐỘNG TÔU
*******************************************************

sum energy_share energy_share_tou
gen delta_share = energy_share_tou - energy_share

* Vẽ biểu đồ thay đổi tỷ trọng chi điện sau chính sách TOU
twoway (hist delta_share), title("Thay đổi tỷ trọng chi điện do TOU") ///
       xtitle("Thay đổi (%)") ytitle("Số hộ")

*******************************************************
* 6. LƯU DỮ LIỆU VÀ KẾT THÚC
*******************************************************

save "VHLSS2022_QAIDS_ready.dta", replace
log close
*******************************************************
