//
//  LineColor.swift
//  Transi
//
//  Created by magic_sk on 03/10/2023.
//

import Foundation
import SwiftUI

func colorFromLineNum(_ lineNum: String) -> Color? {
    switch lineNum {
        case "1":
            return Color.l1
        case "3":
            return Color.l3
        case "4":
            return Color.l4
        case "14":
            return Color.l4
        case "80":
            return Color.l5
        case "99":
            return Color.l6
        case "7":
            return Color.l7
        case "8":
            return Color.l8
        case "9":
            return Color.l9
        case "21":
            return Color.l21
        case "33":
            return Color.l33
        case "37":
            return Color.l37
        case "40":
            return Color.l40
        case "42":
            return Color.l42
        case "44":
            return Color.l44
        case "47":
            return Color.l47
        case "49":
            return Color.l49
        case "50":
            return Color.l50
        case "60":
            return Color.l60
        case "61":
            return Color.l61
        case "63":
            return Color.l63
        case "88":
            return Color.l63
        case "64":
            return Color.l64
        case "68":
            return Color.l68
        case "71":
            return Color.l71
        case "72":
            return Color.l72
        case "83":
            return Color.l83
        case "84":
            return Color.l83
        case "93":
            return Color.l93
        case "94":
            return Color.l93
        case "95":
            return Color.l95
        case "96":
            return Color.l96
        case "98":
            return Color.l98
        case "570":
            return Color.l141
        case "245":
            return Color.l245
        case "255":
            return Color.l255
        case "637":
            return Color.l255
        case "256":
            return Color.l256
        case "257":
            return Color.l257
        case "258":
            return Color.l258
        case "269":
            return Color.l269
        case "523":
            return Color.l523
        case "636":
            return Color.l523
        case "525":
            return Color.l525
        case "527":
            return Color.l525
        case "540":
            return Color.l540
        case "550":
            return Color.l540
        case "610":
            return Color.l610
        case "620":
            return Color.l620
        case "632":
            return Color.l632
        case "720":
            return Color.l720
        case "740":
            return Color.l720
        case "737":
            return Color.l737
        case "298":
            return Color.night_regio
        case "299":
            return Color.night_regio
        case "598":
            return Color.night_regio
        case "599":
            return Color.night_regio
        case "699":
            return Color.night_regio
        case "798":
            return Color.night_regio
        case "799":
            return Color.night_regio
        case "►":
            return Color.secondaryLabel
        default:
            if lineNum.starts(with: "S") || lineNum.starts(with: "R") { return Color.train }
            if lineNum.starts(with: "AT") { return Color.AT_train }
            if lineNum.starts(with: "N") { return Color.night }
            if lineNum.starts(with: "X") { return Color.replacement }
            if Int(lineNum) ?? 0 > 200 { return Color.regio }
            return Color.ldefault
    }
}

func textColorFromLineNum(_ lineNum: String) -> Color? {
    switch lineNum {
        case "7":
            return Color.black
        case "N21":
            return Color.ln21
        case "N29":
            return Color.ln29
        case "N31":
            return Color.ln31
        case "N33":
            return Color.ln33
        case "N34":
            return Color.ln34
        case "N37":
            return Color.ln37
        case "N44":
            return Color.ln44
        case "N47":
            return Color.ln47
        case "N53":
            return Color.ln53
        case "N55":
            return Color.ln55
        case "N56":
            return Color.ln56
        case "N61":
            return Color.ln61
        case "N70":
            return Color.ln70
        case "N72":
            return Color.ln72
        case "N74":
            return Color.ln74
        case "N80":
            return Color.ln80
        case "N91":
            return Color.ln91
        case "N93":
            return Color.ln93
        case "N95":
            return Color.ln95
        case "N99":
            return Color.ln99
        case "298":
            return Color.white
        case "299":
            return Color.white
        case "598":
            return Color.white
        case "599":
            return Color.white
        case "699":
            return Color.white
        case "798":
            return Color.white
        case "799":
            return Color.white
        default:
            if lineNum.starts(with: "X") || Int(lineNum) ?? 0 > 200 { return Color.black }
            return Color.white
    }
}

func isRounded(_ lineNum: String) -> Bool {
    let lineInt = Int(lineNum) ?? 99
    if lineInt < 20 || lineNum.starts(with: "S") || lineNum.starts(with: "R") || lineNum.starts(with: "AT") {
        return true
    } else {
        return false
    }
}
