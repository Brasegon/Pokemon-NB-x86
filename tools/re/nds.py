"""Lecture d'une ROM DS pour la rétro-ingénierie : fichiers NitroFS, archives NARC, code ARM9 et
overlays (décompressés).

La ROM vient de la variable d'environnement POKEMON_ROM, sinon du premier .nds à la racine du
dépôt. Les autres outils de ce dossier lisent tout par ce module ; rien n'est écrit sur le disque.
"""
import glob
import os
import struct
import sys

# Racine du dépôt (ce fichier est dans tools/re/).
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Sorties en UTF-8 (messages d'erreur compris), même redirigées vers un fichier ou vers un
# terminal Git Bash.
sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def s16(b, o):
    return struct.unpack_from("<h", b, o)[0]


def s32(b, o):
    return struct.unpack_from("<i", b, o)[0]


def blz_decompress(data):
    """Décompresse un fichier BLZ (« LZ à l'envers » de l'ARM9 et des overlays) : la fin est
    compressée et se lit en reculant. Renvoie les données telles quelles si le pied de fichier
    indique qu'elles ne sont pas compressées. Même algorithme que Lz.decompress_backward()."""
    data = bytes(data)
    extra = u32(data, len(data) - 4)
    if extra == 0:
        return data
    footer = data[len(data) - 5]
    start = len(data) - (u32(data, len(data) - 8) & 0xFFFFFF)
    out = bytearray(data[:len(data) - footer]) + bytearray(footer + extra)
    src = len(data) - footer
    dst = len(out)
    while src > start:
        src -= 1
        flags = data[src]
        for _ in range(8):
            if src <= start:
                break
            if flags & 0x80:
                pair = (data[src - 1] << 8) | data[src - 2]
                src -= 2
                disp = (pair & 0xFFF) + 3
                for _ in range(min((pair >> 12) + 3, dst - start)):
                    dst -= 1
                    out[dst] = out[dst + disp]
            else:
                src -= 1
                dst -= 1
                out[dst] = data[src]
            flags = (flags << 1) & 0xFF
    return bytes(out)


def narc_files(b):
    """Sous-fichiers d'une archive NARC (sections BTAF, BTNF, GMIF)."""
    if b[:4] != b"NARC":
        raise ValueError("pas une archive NARC")
    p = u16(b, 0x0C)
    count = u16(b, p + 8)
    entries = [struct.unpack_from("<2I", b, p + 12 + 8 * i) for i in range(count)]
    p += u32(b, p + 4)
    p += u32(b, p + 4)
    base = p + 8
    return [b[base + s:base + e] for s, e in entries]


class Rom:
    def __init__(self, path=None):
        if path is None:
            path = os.environ.get("POKEMON_ROM")
        if not path:
            candidates = sorted(glob.glob(os.path.join(ROOT, "*.nds")))
            if not candidates:
                sys.exit("Aucune ROM : définir POKEMON_ROM ou poser le .nds à la racine du dépôt.")
            path = candidates[0]
        with open(path, "rb") as f:
            self.data = f.read()
        h = self.data[:0x200]
        self.game_code = h[0x0C:0x10].decode("ascii")
        self.arm9_offset, self.arm9_entry, self.arm9_ram, self.arm9_size = struct.unpack_from("<4I", h, 0x20)
        fnt_offset, _, fat_offset, fat_size = struct.unpack_from("<4I", h, 0x40)
        table_offset, table_size = struct.unpack_from("<2I", h, 0x50)
        self.fat = [struct.unpack_from("<2I", self.data, fat_offset + 8 * i) for i in range(fat_size // 8)]
        self.paths = {}
        self._read_dir(fnt_offset, 0xF000, "")
        self.overlay_table = []
        for i in range(table_size // 32):
            e = struct.unpack_from("<8I", self.data, table_offset + 32 * i)
            self.overlay_table.append({"id": e[0], "ram": e[1], "ram_size": e[2], "bss_size": e[3],
                                       "sinit": (e[4], e[5]), "file_id": e[6],
                                       "compressed": bool(e[7] >> 24 & 1)})

    def _read_dir(self, fnt, dir_id, prefix):
        entries, file_id = struct.unpack_from("<IH", self.data, fnt + 8 * (dir_id & 0xFFF))
        p = fnt + entries
        while self.data[p]:
            kind = self.data[p]
            name = self.data[p + 1:p + 1 + (kind & 0x7F)].decode("latin-1")
            p += 1 + (kind & 0x7F)
            if kind & 0x80:
                self._read_dir(fnt, u16(self.data, p), prefix + name + "/")
                p += 2
            else:
                self.paths[prefix + name] = file_id
                file_id += 1

    def file(self, key):
        """Fichier par son chemin (« a/0/0/8 ») ou son numéro dans la FAT."""
        start, end = self.fat[self.paths[key] if isinstance(key, str) else key]
        return self.data[start:end]

    def narc(self, key):
        return narc_files(self.file(key))

    def arm9(self):
        """(adresse en mémoire, code décompressé) de l'exécutable ARM9. La fin de la partie
        compressée est dans les paramètres du module (repérés par 0xDEC00621 0x2106C0DE)."""
        code = self.data[self.arm9_offset:self.arm9_offset + self.arm9_size]
        params = code.find(bytes.fromhex("2106C0DEDEC00621")) - 0x1C
        compressed_end = u32(code, params + 0x14)
        if compressed_end:
            end = compressed_end - self.arm9_ram
            code = blz_decompress(code[:end]) + code[end:]
        return self.arm9_ram, code

    def arm9_layout(self):
        """Découpage de l'ARM9 décompressé, d'après les paramètres du module :
        (adresse, code fixe, (début, fin) de son bss, sections recopiées au démarrage).

        Les sections (ITCM en 0x01FF8000, DTCM en 0x02FE0000...) suivent le code fixe dans le
        fichier, dans l'ordre de leur liste : entrées de 16 octets (adresse, taille, l'adresse
        encore, taille du bss). Leurs tailles s'additionnent exactement jusqu'au début de la liste.
        Le bss du code fixe commence là où ces données commencent (elles sont recopiées ailleurs
        au démarrage, la place est ensuite réutilisée). Chaque section : (adresse, contenu, taille
        du bss)."""
        ram, code = self.arm9()
        params = code.find(bytes.fromhex("2106C0DEDEC00621")) - 0x1C
        list_start, list_end, data_start, bss_start, bss_end = struct.unpack_from("<5I", code, params)
        sections = []
        pos = data_start - ram
        for entry in range(list_start - ram, list_end - ram, 16):
            address, size, _, bss_size = struct.unpack_from("<4I", code, entry)
            sections.append((address, code[pos:pos + size], bss_size))
            pos += size
        assert pos == list_start - ram, "sections de l'ARM9 mal découpées"
        return ram, code[:data_start - ram], (bss_start, bss_end), sections

    def overlay(self, index):
        """(adresse en mémoire, contenu décompressé) de l'overlay ARM9 n° index."""
        entry = self.overlay_table[index]
        raw = self.file(entry["file_id"])
        return entry["ram"], blz_decompress(raw) if entry["compressed"] else raw

    def code_blobs(self):
        """[(nom, adresse en mémoire, contenu)] pour l'ARM9 puis chaque overlay."""
        ram, code = self.arm9()
        blobs = [("arm9", ram, code)]
        for i in range(len(self.overlay_table)):
            blobs.append(("ov%03d" % i,) + self.overlay(i))
        return blobs
