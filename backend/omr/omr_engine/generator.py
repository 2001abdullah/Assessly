"""
Printable OMR sheet generator.

Draws an :class:`OMRTemplate` to a print-ready PDF with ReportLab.  The PDF is
the *only* artefact the operator prints, and the scanner reads sheets back using
the exact same coordinates, so the two can never drift apart.

Coordinate note: the template uses millimetres with the origin at the top-left
and +y downward; ReportLab uses points with the origin at the bottom-left and +y
upward.  :func:`_pt` and :func:`_y` do the conversion in one place.
"""

from __future__ import annotations

import io
from typing import List, Optional

from reportlab.lib.colors import Color, black, white
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas as rl_canvas
from reportlab.pdfbase import pdfmetrics

from .template import OMRTemplate, TextBox

# Grey used for bubble outlines and rule lines.  Light enough that the printed
# ring barely registers in the sampled disc, dark enough to be easy to aim at.
BUBBLE_STROKE = Color(0.45, 0.45, 0.45)
BOX_STROKE = Color(0.55, 0.55, 0.55)
RULE = Color(0.80, 0.80, 0.80)
LABEL_GREY = Color(0.25, 0.25, 0.25)


def _pt(v_mm: float) -> float:
    return v_mm * mm


class SheetRenderer:
    def __init__(self, template: OMRTemplate):
        self.t = template

    # y flip -------------------------------------------------------------- #
    def _y(self, y_mm: float) -> float:
        return _pt(self.t.page_h_mm - y_mm)

    # ---------------------------------------------------------------- API #
    def render(self, path: str, copies: int = 1, serials: Optional[List[str]] = None) -> str:
        c = rl_canvas.Canvas(
            path, pagesize=(_pt(self.t.page_w_mm), _pt(self.t.page_h_mm))
        )
        c.setTitle(self.t.name)
        c.setSubject(f"OMR answer sheet - template {self.t.template_id}")
        for i in range(max(1, copies)):
            serial = serials[i] if serials and i < len(serials) else None
            self._draw_page(c, serial)
            c.showPage()
        c.save()
        return path

    def render_bytes(self, copies: int = 1, serials: Optional[List[str]] = None) -> bytes:
        buf = io.BytesIO()
        c = rl_canvas.Canvas(buf, pagesize=(_pt(self.t.page_w_mm), _pt(self.t.page_h_mm)))
        c.setTitle(self.t.name)
        for i in range(max(1, copies)):
            serial = serials[i] if serials and i < len(serials) else None
            self._draw_page(c, serial)
            c.showPage()
        c.save()
        return buf.getvalue()

    # ------------------------------------------------------------- drawing #
    def _draw_page(self, c: rl_canvas.Canvas, serial: Optional[str]) -> None:
        self._draw_frame(c)
        self._draw_fiducials(c)
        self._draw_timing(c)
        self._draw_texts(c)
        self._draw_bubbles(c)
        self._draw_qr(c, serial)
        self._draw_footer(c, serial)

    def _draw_frame(self, c: rl_canvas.Canvas) -> None:
        t = self.t
        x0, y0, x1, y1 = t.roi
        c.setStrokeColor(RULE)
        c.setLineWidth(0.5)
        c.rect(_pt(x0), self._y(y1), _pt(x1 - x0), _pt(y1 - y0), stroke=1, fill=0)

        # a light rule under the header, above the question block
        q_top = t.meta.get("question_top_mm")
        if q_top:
            c.setStrokeColor(RULE)
            c.setLineWidth(0.6)
            c.line(_pt(x0 + 2), self._y(q_top - 2.5), _pt(x1 - 2), self._y(q_top - 2.5))

    def _draw_fiducials(self, c: rl_canvas.Canvas) -> None:
        for f in self.t.fiducials:
            half = f.size_mm / 2.0
            # white quiet zone first so nothing else can touch the marker
            c.setFillColor(white)
            c.setStrokeColor(white)
            q = half + f.quiet_mm
            c.rect(_pt(f.x_mm - q), self._y(f.y_mm + q), _pt(2 * q), _pt(2 * q),
                   stroke=0, fill=1)
            c.setFillColor(black)
            c.rect(_pt(f.x_mm - half), self._y(f.y_mm + half),
                   _pt(f.size_mm), _pt(f.size_mm), stroke=0, fill=1)

    def _draw_timing(self, c: rl_canvas.Canvas) -> None:
        c.setFillColor(black)
        for track in self.t.timing_tracks:
            for y in track.y_positions_mm:
                c.rect(
                    _pt(track.x_mm - track.w_mm / 2.0),
                    self._y(y + track.h_mm / 2.0),
                    _pt(track.w_mm),
                    _pt(track.h_mm),
                    stroke=0,
                    fill=1,
                )

    def _draw_texts(self, c: rl_canvas.Canvas) -> None:
        for tb in self.t.texts:
            if tb.box:
                c.setStrokeColor(BOX_STROKE)
                c.setLineWidth(0.5)
                c.roundRect(_pt(tb.x_mm), self._y(tb.y_mm + tb.h_mm),
                            _pt(tb.w_mm), _pt(tb.h_mm), _pt(0.8), stroke=1, fill=0)
            if not tb.text:
                continue
            font = "Helvetica-Bold" if tb.bold else "Helvetica"
            c.setFont(font, tb.font_size)
            c.setFillColor(black if tb.bold else LABEL_GREY)
            lines = _wrap(tb.text, font, tb.font_size, _pt(tb.w_mm))
            # baseline of the first line, a hair below the top of the box
            ty = self._y(tb.y_mm) - tb.font_size * 0.92
            for line in lines:
                if tb.align == "center":
                    c.drawCentredString(_pt(tb.x_mm + tb.w_mm / 2.0), ty, line)
                elif tb.align == "right":
                    c.drawRightString(_pt(tb.x_mm + tb.w_mm), ty, line)
                else:
                    c.drawString(_pt(tb.x_mm), ty, line)
                ty -= tb.font_size * 1.12

    def _draw_bubbles(self, c: rl_canvas.Canvas) -> None:
        c.setStrokeColor(BUBBLE_STROKE)
        c.setLineWidth(0.45)
        c.setFillColor(white)
        for g in self.t.groups:
            for b in g.bubbles:
                c.circle(_pt(b.x_mm), self._y(b.y_mm), _pt(b.r_mm), stroke=1, fill=0)

    def _draw_qr(self, c: rl_canvas.Canvas, serial: Optional[str]) -> None:
        t = self.t
        payload = t.qr_payload if not serial else f"{t.qr_payload}|{serial}"
        try:
            import qrcode  # local import: only needed when drawing

            qr = qrcode.QRCode(border=1, box_size=4,
                               error_correction=qrcode.constants.ERROR_CORRECT_M)
            qr.add_data(payload)
            qr.make(fit=True)
            img = qr.make_image(fill_color="black", back_color="white").convert("RGB")
            buf = io.BytesIO()
            img.save(buf, format="PNG")
            buf.seek(0)
            from reportlab.lib.utils import ImageReader

            c.drawImage(ImageReader(buf), _pt(t.qr_x_mm), self._y(t.qr_y_mm + t.qr_size_mm),
                        _pt(t.qr_size_mm), _pt(t.qr_size_mm))
        except Exception:  # pragma: no cover - QR is a convenience, not a requirement
            c.setStrokeColor(RULE)
            c.rect(_pt(t.qr_x_mm), self._y(t.qr_y_mm + t.qr_size_mm),
                   _pt(t.qr_size_mm), _pt(t.qr_size_mm), stroke=1, fill=0)

    def _draw_footer(self, c: rl_canvas.Canvas, serial: Optional[str]) -> None:
        t = self.t
        c.setFont("Helvetica", 5.4)
        c.setFillColor(LABEL_GREY)
        txt = f"template {t.template_id}"
        if serial:
            txt += f"   sheet {serial}"
        c.drawString(_pt(t.roi[0]), self._y(t.page_h_mm - 4.0), txt)


def _wrap(text: str, font: str, size: float, max_w_pt: float) -> List[str]:
    """Greedy word wrap using real font metrics."""
    words = text.split()
    if not words:
        return []
    lines: List[str] = []
    cur = words[0]
    for w in words[1:]:
        trial = f"{cur} {w}"
        if pdfmetrics.stringWidth(trial, font, size) <= max_w_pt:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    return lines


def generate_sheet_pdf(template: OMRTemplate, path: str, copies: int = 1,
                       serials: Optional[List[str]] = None) -> str:
    """Convenience wrapper: render ``template`` to ``path``."""
    return SheetRenderer(template).render(path, copies=copies, serials=serials)
