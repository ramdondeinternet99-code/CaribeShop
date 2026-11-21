"""P1.2 - Perfil escalonado (subida, carga sostenida, bajada) de 35 minutos.

Reutiliza el locustfile de demo-escalamiento: cada respuesta registra una fila
"BACKEND <instancia>" para ver en vivo cuantas instancias atienden (y cuando aparece la nueva).
OJO: la fila Aggregated (y los CSV) incluyen esas filas sinteticas BACKEND, por lo que
su RPS aparece duplicado. Para el throughput real use las filas /work + /api/info
(o: python3 scripts/resumen_locust.py evidencias/p1/escalonada_stats_history.csv).

Uso (desde la raiz del repo):
  export PEAK_USERS=40       # calculelo con la prueba de capacidad (P1.1)
  locust -f tests/locustfile.py --host http://<IP_LB> --headless \
         --csv evidencias/p1/escalonada --csv-full-history \
         --html evidencias/p1/escalonada.html
Con interfaz web (demo): quite --headless y abra http://localhost:8089.
Con LoadTestShape, Locust ignora -u/-r/-t: la forma manda.
"""
import os

from locust import HttpUser, LoadTestShape, between, events, task

PEAK_USERS = int(os.environ.get("PEAK_USERS", "40"))
TRABAJO_MS = int(os.environ.get("TRABAJO_MS", "150"))


def registrar_backend(user, resp):
    host = resp.headers.get("X-Served-By", "desconocido")
    user.environment.events.request.fire(
        request_type="BACKEND",
        name=host,
        response_time=resp.elapsed.total_seconds() * 1000,
        response_length=0,
        exception=None,
        context={},
    )


class Comprador(HttpUser):
    wait_time = between(0.5, 1.5)

    @task(1)
    def info(self):
        with self.client.get("/api/info", name="/api/info", catch_response=True) as r:
            if r.status_code == 200:
                registrar_backend(self, r)
                r.success()
            else:
                r.failure(f"HTTP {r.status_code}")

    @task(5)
    def trabajo(self):
        with self.client.get(f"/work?ms={TRABAJO_MS}", name="/work", catch_response=True) as r:
            if r.status_code == 200:
                registrar_backend(self, r)
                r.success()
            else:
                r.failure(f"HTTP {r.status_code}")


class PerfilEscalonado(LoadTestShape):
    # (minuto_final_de_la_etapa, fraccion_del_pico)
    etapas = [
        (3, 0.15),   # calentamiento
        (8, 0.60),   # subida
        (18, 1.00),  # carga sostenida (pico): dispara el scale-out
        (22, 0.30),  # bajada
        (35, 0.05),  # cola larga para observar el scale-in
    ]

    def tick(self):
        minutos = self.get_run_time() / 60
        for fin, fraccion in self.etapas:
            if minutos < fin:
                return max(1, int(PEAK_USERS * fraccion)), max(1, PEAK_USERS // 20)
        return None


@events.test_start.add_listener
def al_iniciar(environment, **kwargs):
    print(f"Prueba contra {environment.host} | PEAK_USERS={PEAK_USERS} TRABAJO_MS={TRABAJO_MS}")
