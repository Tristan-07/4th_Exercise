/**
 * Reports & System Analytics Logic Module
 * Systems Analysis and Design — Lab 4
 */

async function fetchSystemMetrics() {
  const [equipRes, reqRes, userRes] = await Promise.all([
    supabaseClient.from('equipment').select('*'),
    supabaseClient.from('borrowing_requests').select('*'),
    supabaseClient.from('profiles').select('*')
  ]);

  if (equipRes.error) throw equipRes.error;
  if (reqRes.error) throw reqRes.error;
  if (userRes.error) throw userRes.error;

  const equipment = equipRes.data || [];
  const requests = reqRes.data || [];
  const users = userRes.data || [];

  return {
    totalEquipment: equipment.length,
    availableEquipment: equipment.filter(e => e.status === 'Available').length,
    borrowedEquipment: equipment.filter(e => e.status === 'Borrowed').length,
    maintenanceEquipment: equipment.filter(e => e.status === 'Maintenance').length,
    damagedEquipment: equipment.filter(e => e.status === 'Damaged' || e.status === 'Unserviceable').length,

    totalRequests: requests.length,
    pendingRequests: requests.filter(r => r.status === 'Pending').length,
    approvedRequests: requests.filter(r => r.status === 'Approved').length,
    rejectedRequests: requests.filter(r => r.status === 'Rejected').length,
    releasedRequests: requests.filter(r => r.status === 'Released').length,
    returnedRequests: requests.filter(r => r.status === 'Returned').length,

    totalUsers: users.length,
    adminUsers: users.filter(u => u.role === 'administrator').length,
    staffUsers: users.filter(u => u.role === 'laboratory_staff').length,
    requesterUsers: users.filter(u => u.role === 'requester').length
  };
}
