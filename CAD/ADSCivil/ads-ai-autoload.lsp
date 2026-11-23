;; ========================================================
;; ADSCivil AI (MCP) - tu nap module AI luc khoi dong ZWCAD.
;;
;; Dan doan nay vao CUOI file ZWCAD.lsp trong thu muc cai ADSCivil
;; (scripts\install-2026-autoload.ps1 lam viec nay tu dong).
;;
;; Can co trong cung thu muc (hoac trong support path cua ZWCAD):
;;   Ads.System.AI.Assistant.zrx, AdsMcpServer.exe, AdsAI\
;; Lenh mo bang chat: ADSAI
;; Chi nap neu tim thay file va chua nap; loi thi bao 1 dong, khong lam hong menu.
;; ========================================================
(defun ads-ai-autoload ( / zrx res)
  (setq zrx (findfile "Ads.System.AI.Assistant.zrx"))
  (cond
    ((null zrx)
      (princ "\nADSCivil AI: khong tim thay Ads.System.AI.Assistant.zrx."))
    ((vl-some '(lambda (a) (wcmatch (strcase a) "*ADS.SYSTEM.AI.ASSISTANT*")) (arx))
      nil)
    (T
      (setq res (vl-catch-all-apply 'arxload (list zrx "ADSAI-LOADFAIL")))
      (if (or (vl-catch-all-error-p res) (= res "ADSAI-LOADFAIL"))
        (princ "\nADSCivil AI: khong nap duoc module AI.")
        (princ "\nADSCivil AI: da nap. Go ADSAI de mo tro ly AI.")
      )
    )
  )
  (princ)
)
(ads-ai-autoload)
