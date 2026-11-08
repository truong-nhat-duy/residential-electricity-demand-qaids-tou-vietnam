use "D:\Downloads\Ngành Kinh tế phát triển UEH\Phân tích hành vi người tiêu dùng\Bài cuối kỳ\data bài cuối kỳ\final.dta"
global controls ln_price ln_nhietdo ln_lgmua ln_dtnha tsnguoi sonha i.ttnt i.gtinh i.dantoc i.vlmai i.vltuong i.loainha i.shnha2
* Phân vị 25%
qreg ln_lgdien ln_thubq ln_thubq2 $controls, quantile(0.25)
* Phân vị 50% (median)
qreg ln_lgdien ln_thubq ln_thubq2 $controls, quantile(0.50)
* Phân vị 75%
qreg ln_lgdien ln_thubq ln_thubq2 $controls, quantile(0.75)
* B2.1: Mô hình Engel bán tham số
npregress series ln_lgdien ln_thubq, asis(ln_price ln_nhietdo ln_lgmua ln_dtnha tsnguoi sonha i.ttnt i.gtinh i.dantoc i.vlmai i.vltuong i.loainha i.shnha2)
* B2.2: Vẽ tác động biên của ln_thubq (kiểm tra phi tuyến)
margins, at(ln_thubq=(6(0.5)10)) dydx(ln_thubq)
marginsplot, title("Tác động biên của ln(thu nhập) lên ln(điện tiêu thụ) - mô hình bán tham số")
reg ln_thubq ln_price ln_nhietdo ln_lgmua ln_dtnha tsnguoi sonha    i.ttnt i.gtinh i.dantoc i.vlmai i.vltuong i.loainha i.shnha2
predict vhat, resid
summarize vhat
* Center các biến liên tục
capture drop c_ln_price c_ln_nhietdo c_ln_lgmua c_ln_dtnha c_tsnguoi c_sonha

sum ln_price
gen c_ln_price   = ln_price   - r(mean)

sum ln_nhietdo
gen c_ln_nhietdo = ln_nhietdo - r(mean)

sum ln_lgmua
gen c_ln_lgmua   = ln_lgmua   - r(mean)

sum ln_dtnha
gen c_ln_dtnha   = ln_dtnha   - r(mean)

sum tsnguoi
gen c_tsnguoi    = tsnguoi    - r(mean)

sum sonha
gen c_sonha      = sonha      - r(mean)

* Tạo các IV kiểu Lewbel: residual * centered exogenous
capture drop z1 z2 z3 z4 z5 z6
gen z1 = c_ln_price   * vhat
gen z2 = c_ln_nhietdo * vhat
gen z3 = c_ln_lgmua   * vhat
gen z4 = c_ln_dtnha   * vhat
gen z5 = c_tsnguoi    * vhat
gen z6 = c_sonha      * vhat
summarize z1 z2 z3 z4 z5 z6
*OLS
ivregress 2sls ln_lgdien ln_price ln_nhietdo ln_lgmua ln_dtnha tsnguoi sonha i.ttnt i.gtinh i.dantoc i.vlmai i.vltuong i.loainha i.shnha2 (ln_thubq = z1 z2 z3 z4 z5 z6), robust
estat firststage
estat endogenous
reg ln_lgdien ln_thubq ln_thubq2 ln_price ln_nhietdo ln_lgmua ln_dtnha tsnguoi sonha i.ttnt i.gtinh i.dantoc i.vlmai i.vltuong i.loainha i.shnha2, robust
* B4.2: Tính điểm uốn của ln(thu nhập)
scalar b1 = _b[ln_thubq]
scalar b2 = _b[ln_thubq2]
scalar lnY_star = -b1/(2*b2)
display "Turning point (ln thu nhập) = " lnY_star
scalar Y_star = exp(lnY_star)
display "Thu nhập bình quân đầu người tại điểm uốn = " Y_star
* B4.3: Tác động biên của ln_thubq ở các mức khác nhau
margins, dydx(ln_thubq) at(ln_thubq=(6 7 8 9 10 11))
marginsplot, title("Tác động biên của thu nhập lên cầu điện (OLS parabol)") ytitle("d ln(Electricity) / d ln(Income)") xtitle("ln(Thu nhập bình quân đầu người)")

