#!/usr/bin/env python3
"""Redeploy the Destroyer core + mra to MiSTer boards after a Quartus build.

Uso:  python deploy_destroyer.py
Sube el .rbf (output_files/Destroyer.rbf) como `destroyer_YYYYMMDD.rbf` y la .mra
a las placas por SFTP, verifica el tamano remoto y hace sync.

Config por variables de entorno:
  MISTER_HOSTS  lista separada por comas (def: 192.168.5.123)
  MISTER_USER   usuario ssh   (def: root)
  MISTER_PW     password ssh  (def: 1 = default de MiSTer)
"""
import os
import sys
import paramiko

# --- nomenclatura estandar: <corename>_YYYYMMDD.rbf + "Nombre (Fabricante, Anyo).mra" ---
CORENAME = "destroyer"
DATE = "20260702"
MRA_NAME = "Destroyer (Cidelsa, 1980).mra"

HOSTS = [h.strip() for h in os.getenv("MISTER_HOSTS", "192.168.5.123").split(",") if h.strip()]
USER = os.getenv("MISTER_USER", "root")
PW = os.getenv("MISTER_PW", "1")   # default de MiSTer; NO hardcodear otro aqui

BASE = os.path.dirname(os.path.abspath(__file__))
RBF = os.path.join(BASE, "output_files", "Destroyer.rbf")        # salida de Quartus (revision Destroyer)
MRA = os.path.join(BASE, "..", "releases", MRA_NAME)             # descargable canonico en releases/

FILES = [
    (RBF, f"/media/fat/_Arcade/cores/{CORENAME}_{DATE}.rbf"),
    (MRA, f"/media/fat/_Arcade/{MRA_NAME}"),
]


def main():
    if not os.path.exists(RBF):
        sys.exit(f"ERROR: no existe {RBF} -- el build no ha terminado o fallo.")
    print(f"Local  {os.path.basename(RBF)} = {os.path.getsize(RBF)} bytes -> {CORENAME}_{DATE}.rbf")
    for host in HOSTS:
        try:
            c = paramiko.SSHClient()
            c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            c.connect(host, username=USER, password=PW, timeout=25,
                      look_for_keys=False, allow_agent=False)
            sftp = c.open_sftp()
            for lp, rp in FILES:
                sftp.put(lp, rp)
                print(f"  {host} {os.path.basename(rp):28s} -> {sftp.stat(rp).st_size} bytes")
            sftp.close()
            c.exec_command("sync")
            c.close()
            print(f"  {host} OK")
        except Exception as e:
            print(f"  {host} FALLO: {e}")


if __name__ == "__main__":
    main()
