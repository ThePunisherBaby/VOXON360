#include "services/services.hpp"

namespace voxon::services {

void registerAll(Registry& registry) {
  registerSystem(registry);
  registerBusiness(registry);
  registerUsers(registry);
  registerCatalog(registry);
  registerCustomers(registry);
  registerCash(registry);
  registerSales(registry);
  registerFiscal(registry);
  registerInventory(registry);
  registerRestaurant(registry);
  registerReports(registry);
  registerCloud(registry);
}

}  // namespace voxon::services
