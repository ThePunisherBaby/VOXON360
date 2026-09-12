#pragma once

#include "core/engine.hpp"

// Cada módulo registra sus métodos de la API. Ver backend/README.md para la
// lista completa de métodos, parámetros y permisos.
namespace voxon::services {

void registerAll(Registry& registry);

void registerSystem(Registry& registry);
void registerBusiness(Registry& registry);
void registerUsers(Registry& registry);
void registerCatalog(Registry& registry);
void registerCustomers(Registry& registry);
void registerCash(Registry& registry);
void registerSales(Registry& registry);
void registerInventory(Registry& registry);
void registerRestaurant(Registry& registry);
void registerFiscal(Registry& registry);
void registerReports(Registry& registry);
void registerCloud(Registry& registry);

}  // namespace voxon::services
