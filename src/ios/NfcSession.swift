//
//  NfcSession.swift
//  nfcchecker
//
//  Created by 渡邊 信也 on 2022/09/15.
//

// callback用NFCセッション
import Foundation
import UIKit
import CoreNFC

@available(iOS 13, *)
@objc(NfcSession) class NfcSession: CDVPlugin, NFCTagReaderSessionDelegate {
    // エラー時の返却テキスト
    let connectError: String = "読み取りに失敗しました。再度お試しください。"
    let noMiFare: String = "ハピホテタッチNではありません。"
    // システムで表示するテキスト
    let startMessage: String = "ハピホテタッチNにかざしてください"
    let errorMessage: String = "読み取れませんでした"
    var session: NFCTagReaderSession?
    var pluginResult = CDVPluginResult (status: CDVCommandStatus_ERROR, messageAs: "読み取れませんでした");
    var command: CDVInvokedUrlCommand?
    var uid : String = ""
    var locked : String = ""
    var recordCount : String = ""
    var nfcVersion : String = ""
    var recordData: Data? = nil

    //callback success with data
    func cdvCallbackSuccess(message: String = "") {
        var result = [String: String]()

        if(!message.isEmpty) {
            result["message"] = message
        }

        if(!self.locked.isEmpty) {
            result["locked"] = self.locked
        }

        if(!self.recordCount.isEmpty) {
            result["recordCount"] = self.recordCount
        }

        if(!self.uid.isEmpty) {
            result["uid"] = self.uid
        }

        if(!self.nfcVersion.isEmpty) {
            result["version"] = self.nfcVersion
        }

        self.pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: result);
        self.commandDelegate!.send(self.pluginResult, callbackId: self.command!.callbackId);
    }

    func cdvCallbackError() {
        self.pluginResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: self.connectError);
        self.commandDelegate!.send(self.pluginResult, callbackId: self.command!.callbackId);
    }

    @objc(beginScan:)
    func beginScan(command: CDVInvokedUrlCommand) {
        print("beginScan")
        self.command = command
        self.session = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self)
        self.session?.alertMessage = self.startMessage
        self.session?.begin()
    }

    @objc(getRecordData:)
    func getRecordData(command: CDVInvokedUrlCommand) {
        if(self.recordData != nil) {
            var cdvResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "self.recordData!");
            self.commandDelegate!.send(cdvResult, callbackId: command.callbackId);
        }
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // 何もしない
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // 画面を閉じる
        self.session = nil
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        // 複数検出した場合
        
        if tags.count > 1 {
            self.cdvCallbackError()
            self.session?.invalidate(errorMessage: self.errorMessage)
        }
        
        // タグがなかった場合
        guard let tag = tags.first else {
            self.cdvCallbackError()
            self.session?.invalidate(errorMessage: self.errorMessage)
            return
        }

        if case .miFare(let miFareTag) = tag {
            
            // UID
            self.uid = miFareTag.identifier.map{ String(format:"%.2hhx", $0)}.joined()

            self.session?.connect(to: tag) { error in
                if error != nil {
                    self.cdvCallbackSuccess(message: self.connectError)
                    self.session?.invalidate(errorMessage: self.errorMessage)
                }
                
                miFareTag.queryNDEFStatus { status, capacity, error in
                    if error != nil {
                        self.cdvCallbackSuccess(message: self.connectError)
                        self.session?.invalidate(errorMessage: self.errorMessage)
                    }
                    // ロック情報
                    self.locked = status == .readOnly ? "true" : "false"

                    miFareTag.readNDEF { message, error in
                        // エラーの有無確認
                        if let error = error {
                            if (error as NSError).code == 403 {
                                // 403 はレコードを未編集時のエラーのため正しい
                                self.recordCount = String(0)
                            } else {
                                // 403以外のエラーはエラーとして処理する
                                self.cdvCallbackSuccess(message: self.connectError)
                                self.session?.invalidate(errorMessage: self.errorMessage)
                                return
                            }
                        } else {
                            // エラーがなかったのでmessageのrecordsを取得
                            if( message?.records != nil) {
                                let records = message!.records
                                self.recordCount = String(records.count)
                                
                                if(records.count > 0) {
                                    if records[0].payload.count > 0 {
                                        self.recordData = records[0].payload
                                    }
                                }

                            } else {
                                self.cdvCallbackSuccess(message: self.connectError)
                                self.session?.invalidate(errorMessage: self.errorMessage)
                            }

                        }
                        
                        // getVersion
                        miFareTag.sendMiFareCommand(commandPacket: Data([0x60])) { data, error in
                            if error != nil {
                                self.cdvCallbackSuccess(message: self.connectError)
                                self.session?.invalidate(errorMessage: self.errorMessage)
                            }

                            //convert data to hex string
                            self.nfcVersion = data.hexEncodedString()
                            self.cdvCallbackSuccess()
                            self.session?.invalidate()
                        }
                    }
                }
            }
        } else {
            self.cdvCallbackSuccess(message: self.noMiFare)
            self.session?.invalidate()
        }
    }
}

extension Data {
    
    func hexEncodedString() -> String {
        let format = "%02hhX"
        return map { String(format: format, $0) }.joined()
    }
}
