#!/usr/bin/env python3
"""翻译打包:
  make_strings.py --merge        把翻译员交来的 tr_<语言>.json 合并进 translations.json
  make_strings.py <Resources目录> 生成 <语言>.lproj/Localizable.strings (编译时 build_app.sh 调用)
translations.json 的格式: { "中文原文": { "en": "...", "de": "...", ... } }
简体中文直接用原文 (zh-Hans.lproj 是空表, 只用来告诉系统「支持简体中文」)。"""
import json, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
LANGS = ["en", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt", "ru"]
TABLE = HERE / "translations.json"

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

def merge():
    tr = json.loads(TABLE.read_text()) if TABLE.exists() else {}
    for lang in LANGS:
        f = HERE / f"tr_{lang}.json"
        if not f.exists(): continue
        for k, v in json.loads(f.read_text()).items():
            tr.setdefault(k, {})[lang] = v
        f.unlink()
        print(f"merged {f.name}")
    TABLE.write_text(json.dumps(dict(sorted(tr.items())), ensure_ascii=False, indent=1) + "\n")

# Info.plist 里的权限说明 (系统弹窗里显示)
INFOPLIST = {
    "NSDownloadsFolderUsageDescription": {
        "zh-Hans": "查找下载文件夹里很久没用的旧文件", "en": "Find old files in Downloads that you haven’t used for a long time.",
        "zh-Hant": "尋找「下載項目」中很久沒用的舊檔案", "ja": "ダウンロードフォルダ内の長期間使っていない古いファイルを探します。",
        "ko": "다운로드 폴더에서 오랫동안 사용하지 않은 파일을 찾습니다.", "de": "Alte, lange nicht verwendete Dateien im Ordner „Downloads“ finden.",
        "fr": "Trouver les anciens fichiers inutilisés dans Téléchargements.", "es": "Buscar archivos antiguos que no usas desde hace tiempo en Descargas.",
        "pt": "Encontrar arquivos antigos não usados há muito tempo em Downloads.", "ru": "Поиск старых неиспользуемых файлов в папке «Загрузки»."},
    "NSDocumentsFolderUsageDescription": {
        "zh-Hans": "查找占空间的大文件", "en": "Find large files that take up space.", "zh-Hant": "尋找佔用空間的大型檔案",
        "ja": "容量を占めている大きなファイルを探します。", "ko": "공간을 많이 차지하는 대용량 파일을 찾습니다.",
        "de": "Große Dateien finden, die viel Platz belegen.", "fr": "Trouver les fichiers volumineux qui occupent de l’espace.",
        "es": "Buscar archivos grandes que ocupan espacio.", "pt": "Encontrar arquivos grandes que ocupam espaço.",
        "ru": "Поиск больших файлов, занимающих место."},
    "NSAppleEventsUsageDescription": {
        "zh-Hans": "卸载需要管理员权限的应用时，请访达把它移到废纸篓", "en": "When an app needs administrator permission to uninstall, Finder is asked to move it to the Trash.",
        "zh-Hant": "解除安裝需要管理者權限的 App 時，請 Finder 將它移到垃圾桶", "ja": "管理者権限が必要なアプリをアンインストールするとき、Finder にゴミ箱へ移動するよう依頼します。",
        "ko": "관리자 권한이 필요한 앱을 제거할 때 Finder에 휴지통으로 이동하도록 요청합니다.", "de": "Wenn zum Deinstallieren einer App Administratorrechte nötig sind, wird der Finder gebeten, sie in den Papierkorb zu legen.",
        "fr": "Lorsqu’une app nécessite des droits d’administrateur pour être désinstallée, le Finder est chargé de la placer dans la Corbeille.",
        "es": "Si desinstalar una app requiere permisos de administrador, se pide al Finder que la mueva a la Papelera.",
        "pt": "Quando a desinstalação de um app exige permissão de administrador, o Finder é solicitado a movê-lo para o Lixo.",
        "ru": "Если для удаления приложения нужны права администратора, Finder переместит его в Корзину."},
}
INFOPLIST["NSDesktopFolderUsageDescription"] = INFOPLIST["NSDocumentsFolderUsageDescription"]

def write(res):
    tr = json.loads(TABLE.read_text())
    for lang in ["zh-Hans"] + LANGS:
        d = pathlib.Path(res) / f"{lang}.lproj"
        d.mkdir(parents=True, exist_ok=True)
        lines = []
        if lang != "zh-Hans":
            for k, v in tr.items():
                # 缺少某种语言时先用英文, 不要露出中文
                val = v.get(lang) or v.get("en")
                if val: lines.append(f'"{esc(k)}" = "{esc(val)}";')
        (d / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
        info = [f'"{k}" = "{esc(v[lang])}";' for k, v in INFOPLIST.items()]
        (d / "InfoPlist.strings").write_text("\n".join(info) + "\n", encoding="utf-8")
    print(f"wrote {len(LANGS) + 1} languages, {len(tr)} strings -> {res}")

if __name__ == "__main__":
    if sys.argv[1:] == ["--merge"]: merge()
    else: write(sys.argv[1])
