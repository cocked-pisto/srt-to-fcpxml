#!/usr/bin/env python3
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from srt_to_fcpxml import convert


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("SRT → FCPXML 템플릿 변환기")
        self.geometry("680x310")
        self.resizable(True, False)
        self.srt = tk.StringVar()
        self.template = tk.StringVar()
        self.output = tk.StringVar()
        self.status = tk.StringVar(value="SRT와 FCPXML 템플릿을 선택하세요.")
        self._build()

    def _build(self):
        frame = ttk.Frame(self, padding=20)
        frame.pack(fill="both", expand=True)
        ttk.Label(frame, text="사용자 템플릿으로 FCPXML 자막 만들기", font=("Helvetica", 17, "bold")).grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 18))
        self._row(frame, 1, "SRT 파일", self.srt, self._choose_srt)
        self._row(frame, 2, "FCPXML 템플릿", self.template, self._choose_template)
        self._row(frame, 3, "저장 위치", self.output, self._choose_output)
        ttk.Button(frame, text="변환하기", command=self._convert).grid(row=4, column=2, sticky="e", pady=18)
        ttk.Separator(frame).grid(row=5, column=0, columnspan=3, sticky="ew")
        ttk.Label(frame, textvariable=self.status, wraplength=620).grid(row=6, column=0, columnspan=3, sticky="w", pady=12)
        frame.columnconfigure(1, weight=1)

    def _row(self, frame, row, label, variable, command):
        ttk.Label(frame, text=label, width=15).grid(row=row, column=0, sticky="w", pady=5)
        ttk.Entry(frame, textvariable=variable).grid(row=row, column=1, sticky="ew", padx=8)
        ttk.Button(frame, text="선택…", command=command).grid(row=row, column=2)

    def _choose_srt(self):
        value = filedialog.askopenfilename(filetypes=[("SRT 자막", "*.srt"), ("모든 파일", "*.*")])
        if value:
            self.srt.set(value)
            if not self.output.get():
                self.output.set(str(Path(value).with_suffix(".fcpxml")))

    def _choose_template(self):
        value = filedialog.askopenfilename(filetypes=[("Final Cut Pro XML", "*.fcpxml"), ("XML", "*.xml"), ("모든 파일", "*.*")])
        if value:
            self.template.set(value)

    def _choose_output(self):
        value = filedialog.asksaveasfilename(defaultextension=".fcpxml", filetypes=[("Final Cut Pro XML", "*.fcpxml")])
        if value:
            self.output.set(value)

    def _convert(self):
        if not all((self.srt.get(), self.template.get(), self.output.get())):
            messagebox.showwarning("파일 필요", "SRT, 템플릿, 저장 위치를 모두 선택하세요.")
            return
        try:
            count, warnings = convert(Path(self.srt.get()), Path(self.template.get()), Path(self.output.get()))
        except Exception as exc:
            self.status.set(f"변환 실패: {exc}")
            messagebox.showerror("변환 실패", str(exc))
            return
        note = "\n".join(warnings)
        self.status.set(f"완료: 자막 {count}개를 저장했습니다. {note}".strip())
        messagebox.showinfo("변환 완료", f"자막 {count}개를 저장했습니다.\n{self.output.get()}")


if __name__ == "__main__":
    App().mainloop()
