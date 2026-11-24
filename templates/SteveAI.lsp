;; ========================================================
;; Steve AI - lenh mo tro ly AI tu ZWCAD / AutoCAD.
;; File nay do Steve AI Connect tao va tu nap (Startup Suite).
;; Ho tro: Steve Tran | 0987 779 228
;;
;;   AI               lenh tat: mo ngay tro ly AI mac dinh
;;   STEVEAI          mo cua so AI (CL = Claude, CO = Codex, G = Gemini, Enter = mac dinh)
;;   STEVEAI-OPEN     mo ngay tro ly mac dinh
;;   STEVEAI-CLAUDE / STEVEAI-CODEX / STEVEAI-GEMINI
;;   STEVEAI-SKILL    chon mot skill roi mo AI chay skill do
;;   AI-<SKILL>       chay ngay mot skill, vi du AI-CONG-3D
;;   STEVECAD         mo Steve AI Connect (ket noi, danh sach tool)
;;   STEVEAI-SHARE / STEVEAI-FEATURE / STEVEAI-DIAG / STEVEAI-UPDATE / STEVEAI-OPTIONS   mo thang muc do trong Steve AI Connect
;;   Tab ribbon "Steve AI" (file SteveAI.cuix) duoc nap tu dong.
;; ========================================================
(setq *steveai-launcher* "@LAUNCHER@")
(setq *steveai-connect* "@CONNECT@")
(setq *steveai-cuix* "@CUIX@")
(setq *steveai-bin* "@BIN@")
(setq *steveai-skills* '(@SKILLS@))

(defun steveai-ps (file extra)
  (startapp "powershell.exe"
    (strcat "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File \"" file "\"" extra))
)

;; Panel inside the CAD: the plugin is loaded once per session, nobody has to type NETLOAD.
;; Returns T when the panel is shown; nil = open the separate window instead.
;; ZWCAD | AutoCAD / Civil 3D 2021-2024 | 2026 and newer. Other versions: nil = separate window.
(defun steveai-dll ( / v f)
  (setq v (atof (getvar "ACADVER")))
  (setq f (cond ((wcmatch (strcase (getvar "PROGRAM")) "*ZWCAD*") "SteveAIPanel.ZWCAD.dll")
                ((and (>= v 24.0) (< v 25.0)) "SteveAIPanel.ACAD48.dll")
                ((>= v 25.1) "SteveAIPanel.ACADNET.dll")))
  (if f (findfile (strcat *steveai-bin* f)))
)

(defun steveai-panel (client skill / dll fd r *error*)
  ;; Esc or an error while loading must not leave FILEDIA at 0 (no open / save dialogs)
  (defun *error* (m) (if fd (setvar "FILEDIA" fd)) (princ))
  (if (setq dll (steveai-dll))
    (progn
      (vl-load-com)
      (if (and (not steveai-show) (not (vl-bb-ref '*steveai-net*)))
        (progn
          (setq fd (getvar "FILEDIA"))
          (setvar "FILEDIA" 0)
          (vl-catch-all-apply 'vl-cmdf (list "_.NETLOAD" dll))
          (setvar "FILEDIA" fd)
          (setq fd nil)
          (vl-bb-set '*steveai-net* T)
        )
      )
      (setq r (vl-catch-all-apply 'steveai-show (list (if client client "") (if skill skill ""))))
      (and r (not (vl-catch-all-error-p r)))
    )
  )
)

(defun steveai-run (client skill / args)
  (if (not (steveai-panel client skill)) (steveai-window client skill))
  (princ)
)
(defun steveai-window (client skill / args)
  (if (not (findfile *steveai-launcher*))
    (princ "\nSteve AI: khong thay bo mo AI. Mo Steve AI Connect va bam Ket noi lai.")
    (progn
      (setq args "")
      (if client (setq args (strcat args " -Client " client)))
      (if skill (setq args (strcat args " -Skill " skill)))
      (steveai-ps *steveai-launcher* args)
      (princ (strcat "\nSteve AI: dang mo cua so AI" (if skill (strcat " - skill " skill) "") "..."))
    )
  )
  (princ)
)

(defun c:STEVEAI ( / k)
  (initget "CLaude COdex Gemini")
  (setq k (getkword "\nSteve AI - chon tro ly [CLaude/COdex/Gemini] <Enter = mac dinh>: "))
  (steveai-run (cond ((= k "CLaude") "claudecode") ((= k "COdex") "codex") ((= k "Gemini") "gemini")) nil)
)
;; AI: lenh tat, mo ngay tro ly mac dinh (go AI + Enter)
(defun c:AI () (steveai-run nil nil))
(defun c:STEVEAI-OPEN () (steveai-run nil nil))
(defun c:STEVEAI-CLAUDE () (steveai-run "claudecode" nil))
(defun c:STEVEAI-CODEX () (steveai-run "codex" nil))
(defun c:STEVEAI-GEMINI () (steveai-run "gemini" nil))

(defun c:STEVEAI-SKILL ( / i s k)
  (if (null *steveai-skills*)
    (princ "\nSteve AI: chua co skill nao.")
    (progn
      (setq i 0)
      (princ "\nCac skill co san:")
      (foreach s *steveai-skills*
        (setq i (1+ i))
        (princ (strcat "\n  " (itoa i) ". " (car s) " - " (cadr s)))
      )
      (initget 6)
      (setq k (getint (strcat "\nChon skill [1-" (itoa i) "]: ")))
      (if (and k (<= k i))
        (steveai-run nil (car (nth (1- k) *steveai-skills*)))
      )
    )
  )
  (princ)
)

;; part: home | share | feature | diag (report a problem) | help | update | options. A window that is already open is reused.
(defun steveai-open-part (part)
  (if (findfile *steveai-connect*)
    (progn (steveai-ps *steveai-connect* (strcat " -Open " part)) (princ "\nSteve AI: dang mo Steve AI Connect..."))
    (princ "\nSteve AI: khong thay Steve AI Connect. Cai lai tu GitHub steve-trantn/Steve-AI-Connect.")
  )
  (princ)
)
(defun c:STEVECAD () (steveai-open-part "home"))
(defun c:STEVEAI-SHARE () (steveai-open-part "share"))
(defun c:STEVEAI-FEATURE () (steveai-open-part "feature"))
(defun c:STEVEAI-DIAG () (steveai-open-part "diag"))
(defun c:STEVEAI-UPDATE () (steveai-open-part "update"))
(defun c:STEVEAI-OPTIONS () (steveai-open-part "options"))

(defun c:STEVEAI-HELP () (steveai-open-part "help"))

;;@SKILLCMDS@

;; Ribbon tab "Steve AI": load the partial menu once (the CAD remembers it afterwards)
(defun steveai-menu ( / mgs found r)
  ;; AutoCAD / Civil 3D: the plug-in bundle builds the ribbon tab (a CUIX loaded by script stays invisible there)
  (if (and (wcmatch (strcase (getvar "PROGRAM")) "*ZWCAD*") (/= *steveai-cuix* "") (findfile *steveai-cuix*))
    (progn
      (vl-load-com)
      (setq mgs (vla-get-MenuGroups (vlax-get-acad-object)))
      (vlax-for g mgs (if (= (strcase (vla-get-Name g)) "STEVEAI") (setq found T)))
      (if (not found)
        (progn
          (setq r (vl-catch-all-apply 'vla-Load (list mgs *steveai-cuix*)))
          (if (vl-catch-all-error-p r)
            (princ (strcat "\nSteve AI: chua nap duoc tab ribbon (" (vl-catch-all-error-message r) "). Go CUILOAD va chon " *steveai-cuix*))
            (princ "\nSteve AI: da them tab ribbon Steve AI.")
          )
        )
      )
    )
  )
)
;; Loaded by SteveAI.mnl, the menu is being loaded right now: loading it again from here crashed ZWCAD
;; (heap corruption on start). So only load the menu when this file was loaded some other way.
(if *steveai-from-menu*
  (setq *steveai-from-menu* nil)
  (vl-catch-all-apply 'steveai-menu nil)
)

(princ "\nSteve AI: go AI (hoac bam tab ribbon Steve AI) de mo tro ly AI.")
(princ)
