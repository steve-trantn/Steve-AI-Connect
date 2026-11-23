"""Decode Vietnamese text written with legacy fonts (TCVN3/ABC ".VnTime", VNI "VNI-Times") into Unicode.
Drawings made in Vietnam often store such text; read raw, it is gibberish to an AI."""
from __future__ import annotations

import re
import unicodedata

# ---- TCVN3 (ABC): one byte per accented letter
_TCVN3 = {
    "µ": "à", "¸": "á", "¶": "ả", "·": "ã", "¹": "ạ",
    "¨": "ă", "»": "ằ", "¾": "ắ", "¼": "ẳ", "½": "ẵ", "Æ": "ặ",
    "©": "â", "Ç": "ầ", "Ê": "ấ", "È": "ẩ", "É": "ẫ", "Ë": "ậ",
    "®": "đ", "Ì": "è", "Ð": "é", "Î": "ẻ", "Ï": "ẽ", "Ñ": "ẹ",
    "ª": "ê", "Ò": "ề", "Õ": "ế", "Ó": "ể", "Ô": "ễ", "Ö": "ệ",
    "×": "ì", "Ý": "í", "Ø": "ỉ", "Ü": "ĩ", "Þ": "ị",
    "ß": "ò", "ã": "ó", "á": "ỏ", "â": "õ", "ä": "ọ",
    "«": "ô", "å": "ồ", "è": "ố", "æ": "ổ", "ç": "ỗ", "é": "ộ",
    "¬": "ơ", "ê": "ờ", "í": "ớ", "ë": "ở", "ì": "ỡ", "î": "ợ",
    "ï": "ù", "ó": "ú", "ñ": "ủ", "ò": "ũ", "ô": "ụ",
    "­": "ư", "õ": "ừ", "ø": "ứ", "ö": "ử", "÷": "ữ", "ù": "ự",
    "ú": "ỳ", "ý": "ý", "û": "ỷ", "ü": "ỹ", "þ": "ỵ",
    "¡": "Ă", "¢": "Â", "§": "Đ", "£": "Ê", "¤": "Ô", "¥": "Ơ", "¦": "Ư",
}
_TCVN3_MARK = set("µ¸¶·¹¨»¾¼½Æ©ÇÊÈÉË®ÌÐÎÏÑªÒÕÓÔÖ×ÝØÜÞßãáâä«åèæçé¬êíëìîïóñòô­õøö÷ùúûüþ¡¢§£¤¥¦")

# ---- VNI: base letter followed by modifier characters
_TONE = {  # modifier -> combining tone mark
    "ù": "́", "ø": "̀", "û": "̉", "õ": "̃", "ï": "̣",
    "Ù": "́", "Ø": "̀", "Û": "̉", "Õ": "̃", "Ï": "̣",
}
_HAT = {  # circumflex (â ê ô) + tone
    "â": "", "á": "́", "à": "̀", "å": "̉", "ã": "̃", "ä": "̣",
    "Â": "", "Á": "́", "À": "̀", "Å": "̉", "Ã": "̃", "Ä": "̣",
}
_BREVE = {  # breve (ă) + tone
    "ê": "", "é": "́", "è": "̀", "ú": "̉", "ü": "̃", "ë": "̣",
    "Ê": "", "É": "́", "È": "̀", "Ú": "̉", "Ü": "̃", "Ë": "̣",
}
_VNI_SINGLE = {"ö": "ư", "Ö": "Ư", "ô": "ơ", "Ô": "Ơ", "ñ": "đ", "Ñ": "Đ",
               "í": "í", "ì": "ì", "æ": "ỉ", "ó": "ĩ", "ò": "ị",
               "Í": "Í", "Ì": "Ì", "Æ": "Ỉ", "Ó": "Ĩ", "Ò": "Ị"}


def _vni(s: str) -> str:
    out = []
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        nxt = s[i + 1] if i + 1 < n else ""
        low = ch.lower()
        if low in "aeo" and nxt in _HAT:
            base = {"a": "â", "e": "ê", "o": "ô"}[low]
            base = base.upper() if ch.isupper() else base
            out.append(unicodedata.normalize("NFC", base + _HAT[nxt]))
            i += 2
            continue
        if low == "a" and nxt in _BREVE:
            base = "Ă" if ch.isupper() else "ă"
            out.append(unicodedata.normalize("NFC", base + _BREVE[nxt]))
            i += 2
            continue
        if ch in "ôÔöÖ":  # ơ / ư, maybe followed by a tone
            base = _VNI_SINGLE[ch]
            if nxt in _TONE:
                out.append(unicodedata.normalize("NFC", base + _TONE[nxt]))
                i += 2
            else:
                out.append(base)
                i += 1
            continue
        if low in "aeiouy" and nxt in _TONE:
            out.append(unicodedata.normalize("NFC", ch + _TONE[nxt]))
            i += 2
            continue
        out.append(_VNI_SINGLE.get(ch, ch))
        i += 1
    return "".join(out)


_VNI_PATTERN = re.compile(r"[aeiouyAEIOUYôÔöÖ][ùøûõïÙØÛÕÏâáàåãäÂÁÀÅÃÄêéèúüëÊÉÈÚÜË]|[ñÑ][aeiouAEIOU]")
_MTEXT_CODES = re.compile(r"\\[A-Za-z][^;\\]*;|\\[LlOoKkP]|[{}]")


def plain(s: str) -> str:
    """Strip MTEXT formatting codes (\\f...; \\L \\P {...})."""
    s = s.replace("\\P", "\n")
    s = _MTEXT_CODES.sub("", s)
    return s.replace("%%u", "").replace("%%U", "").replace("%%c", "Ø").replace("%%C", "Ø").replace("%%d", "°").replace("%%p", "±")


def detect(s: str, font_hint: str = "") -> str | None:
    f = (font_hint or "").lower()
    if "vni" in f:
        return "vni"
    if f.startswith(".vn") or "vntime" in f or "abc" in f:
        return "tcvn3"
    if any(0x1EA0 <= ord(c) <= 0x1EF9 or c in "ăđơưĂĐƠƯ" for c in s):
        return None  # already Unicode Vietnamese
    vni_hits = len(_VNI_PATTERN.findall(s))
    tc_hits = sum(1 for c in s if c in _TCVN3_MARK)
    if vni_hits and vni_hits * 2 >= tc_hits:
        return "vni"
    if tc_hits:
        return "tcvn3"
    return None


def decode(s: str, font_hint: str = "") -> str:
    """Unicode version of s (MTEXT codes removed). Returns s cleaned if no legacy encoding is detected."""
    if not s:
        return s
    t = plain(s)
    enc = detect(t, font_hint)
    if enc == "tcvn3":
        return "".join(_TCVN3.get(c, c) for c in t)
    if enc == "vni":
        return _vni(t)
    return t
