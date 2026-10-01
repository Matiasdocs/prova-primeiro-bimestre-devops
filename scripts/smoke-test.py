#!/usr/bin/env python3
"""Testa o CRUD real via HTTP; remove somente a reserva criada pelo teste."""
import json
import sys
import urllib.error
import urllib.request

base = (sys.argv[1] if len(sys.argv) > 1 else 'http://localhost:3000').rstrip('/')

def request(method, path, expected, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, method=method,
                                 headers={'Content-Type': 'application/json'})
    try:
        response = urllib.request.urlopen(req, timeout=15)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        raw = response.read()
        result = json.loads(raw) if raw else None
        assert response.status == expected, (method, path, response.status, result)
    print(f'OK {method} {path} -> {expected}')
    return result

reserva = None
try:
    assert request('GET', '/health', 200)['database'] == 'ok'
    request('POST', '/reservas', 400, {'cliente': 'Teste'})
    request('POST', '/reservas', 400, {'cliente': 'Teste', 'data': '2026-02-30', 'status': 'pendente'})
    request('GET', '/reservas/abc', 400)
    request('GET', '/nao-existe', 404)
    reserva = request('POST', '/reservas', 201, {'cliente': "Teste D'Avila", 'data': '2026-10-01', 'status': 'pendente'})
    path = f"/reservas/{reserva['id']}"
    assert request('GET', path, 200) == reserva
    assert any(r['id'] == reserva['id'] for r in request('GET', '/reservas', 200))
    updated = request('PUT', path, 200, {'cliente': 'Teste atualizado', 'data': '2026-10-02', 'status': 'confirmada'})
    assert updated['status'] == 'confirmada'
    assert request('GET', path, 200) == updated
    request('DELETE', path, 204)
    reserva = None
    request('GET', path, 404)
    request('PUT', path, 404, {'cliente': 'Teste', 'data': '2026-10-02', 'status': 'cancelada'})
    request('DELETE', path, 404)
    print('CRUD validado; registro de teste removido.')
finally:
    if reserva is not None:
        request('DELETE', f"/reservas/{reserva['id']}", 204)
