-- Systems Analysis and Design Lab 4
-- Complete Database Schema, RLS & Stored Procedures

-- Automatically drop old conflicting tables from previous labs before creating fresh ones
DROP TABLE IF EXISTS public.audit_logs, public.maintenance_requests, public.borrowing_requests, public.equipment, public.profiles CASCADE;

-- Enable UUID extension if not enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create user profiles table associated with Supabase Auth
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('administrator', 'laboratory_staff', 'requester')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security (RLS) on profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if re-running
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Administrators can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Administrators can update profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Authenticated users can view profiles" ON public.profiles;

-- RLS Policies for profiles:
CREATE POLICY "Authenticated users can view profiles" 
ON public.profiles FOR SELECT 
TO authenticated
USING (true);

CREATE POLICY "Administrators can update profiles" 
ON public.profiles FOR UPDATE 
TO authenticated
USING (public.get_user_role(auth.uid()) = 'administrator');

CREATE POLICY "Users can insert own profile" 
ON public.profiles FOR INSERT 
TO authenticated
WITH CHECK (auth.uid() = id);

-- Trigger Function: Auto-create profile in public.profiles when user registers in auth.users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  v_role TEXT;
BEGIN
  -- Determine role from user metadata, or auto-assign based on email prefix for testing
  v_role := COALESCE(NEW.raw_user_meta_data->>'role', 'requester');
  
  IF NEW.email ILIKE 'admin@%' THEN
    v_role := 'administrator';
  ELSIF NEW.email ILIKE 'staff@%' THEN
    v_role := 'laboratory_staff';
  END IF;

  INSERT INTO public.profiles (id, full_name, email, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    NEW.email,
    v_role
  )
  ON CONFLICT (id) DO UPDATE 
  SET full_name = EXCLUDED.full_name,
      email = EXCLUDED.email,
      role = EXCLUDED.role;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Bind trigger to auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =========================================================
-- HELPER FUNCTIONS & EQUIPMENT SCHEMA
-- =========================================================

-- Helper Function: Get user role safely without triggering RLS recursion
CREATE OR REPLACE FUNCTION public.get_user_role(user_id UUID)
RETURNS TEXT AS $$
  SELECT role FROM public.profiles WHERE id = user_id;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Equipment Table
CREATE TABLE IF NOT EXISTS public.equipment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    equipment_code TEXT UNIQUE,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    condition TEXT NOT NULL DEFAULT 'Good',
    laboratory TEXT NOT NULL DEFAULT 'Main Laboratory',
    status TEXT NOT NULL CHECK (status IN ('Available', 'Borrowed', 'Maintenance', 'Damaged', 'Unserviceable')) DEFAULT 'Available',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Safely alter equipment table to ensure id, equipment_code and all columns exist if table was created in an earlier session
ALTER TABLE public.equipment 
  ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS equipment_code TEXT,
  ADD COLUMN IF NOT EXISTS name TEXT,
  ADD COLUMN IF NOT EXISTS category TEXT,
  ADD COLUMN IF NOT EXISTS quantity INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS condition TEXT DEFAULT 'Good',
  ADD COLUMN IF NOT EXISTS laboratory TEXT DEFAULT 'Main Laboratory',
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'Available';

-- Directly alter column types to TEXT to remove any pre-existing character varying limits
ALTER TABLE public.equipment ALTER COLUMN name TYPE TEXT;
ALTER TABLE public.equipment ALTER COLUMN category TYPE TEXT;
ALTER TABLE public.equipment ALTER COLUMN condition TYPE TEXT;
ALTER TABLE public.equipment ALTER COLUMN laboratory TYPE TEXT;
ALTER TABLE public.equipment ALTER COLUMN status TYPE TEXT;
ALTER TABLE public.equipment ALTER COLUMN equipment_code TYPE TEXT;

-- Handle pre-existing legacy 'equipment_id' column if present from previous table structures
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'equipment' 
          AND column_name = 'equipment_id'
    ) THEN
        -- Set default gen_random_uuid() so inserts without equipment_id do not fail NOT NULL constraints
        ALTER TABLE public.equipment ALTER COLUMN equipment_id SET DEFAULT gen_random_uuid();
        BEGIN
            ALTER TABLE public.equipment ALTER COLUMN equipment_id DROP NOT NULL;
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        UPDATE public.equipment SET equipment_id = COALESCE(id, gen_random_uuid()) WHERE equipment_id IS NULL;
    END IF;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- Populate fallback equipment_code for pre-existing rows if NULL
UPDATE public.equipment 
SET equipment_code = 'EQ-' || SUBSTRING(gen_random_uuid()::text, 1, 6) 
WHERE equipment_code IS NULL;

-- Ensure UNIQUE constraint on equipment_code for ON CONFLICT clause
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'equipment_equipment_code_key'
    ) THEN
        ALTER TABLE public.equipment ADD CONSTRAINT equipment_equipment_code_key UNIQUE (equipment_code);
    END IF;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- Enable RLS on equipment
ALTER TABLE public.equipment ENABLE ROW LEVEL SECURITY;

-- Equipment RLS Policies
DROP POLICY IF EXISTS "Authenticated users can view equipment" ON public.equipment;
CREATE POLICY "Authenticated users can view equipment"
ON public.equipment FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Administrators can manage equipment" ON public.equipment;
CREATE POLICY "Administrators can manage equipment"
ON public.equipment FOR ALL
TO authenticated
USING (public.get_user_role(auth.uid()) = 'administrator');

-- Seed sample equipment data
INSERT INTO public.equipment (equipment_code, name, category, quantity, condition, laboratory, status)
VALUES 
  ('LAP-001', 'Dell XPS 15 Laptop', 'Computers', 5, 'Good', 'Computer Lab A', 'Available'),
  ('OSC-001', 'Digital Oscilloscope DS1054Z', 'Electronics', 3, 'Excellent', 'Electronics Lab B', 'Available'),
  ('MIC-001', 'Binocular Compound Microscope', 'Biology', 4, 'Good', 'Biology Lab C', 'Available'),
  ('PRJ-001', 'Epson LCD Projector HD', 'AV Equipment', 2, 'Fair', 'Multimedia Lab', 'Maintenance'),
  ('3DP-001', 'Ender 3 V2 3D Printer', 'Fabrication', 1, 'Good', 'Maker Lab', 'Available')
ON CONFLICT (equipment_code) DO UPDATE
SET name = EXCLUDED.name,
    category = EXCLUDED.category,
    quantity = EXCLUDED.quantity,
    condition = EXCLUDED.condition,
    laboratory = EXCLUDED.laboratory;

-- Borrowing Requests Table
CREATE TABLE IF NOT EXISTS public.borrowing_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    equipment_id UUID NOT NULL REFERENCES public.equipment(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL DEFAULT 1,
    purpose TEXT NOT NULL,
    requested_date DATE NOT NULL DEFAULT CURRENT_DATE,
    expected_return_date DATE NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('Pending', 'Approved', 'Rejected', 'Released', 'Returned', 'Overdue', 'Closed')) DEFAULT 'Pending',
    approved_by UUID REFERENCES public.profiles(id),
    approved_at TIMESTAMPTZ,
    rejection_reason TEXT,
    released_by UUID REFERENCES public.profiles(id),
    released_at TIMESTAMPTZ,
    returned_by UUID REFERENCES public.profiles(id),
    returned_at TIMESTAMPTZ,
    return_condition TEXT CHECK (return_condition IN ('Good', 'Damaged')),
    return_remarks TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Safely add columns if table already exists
ALTER TABLE public.borrowing_requests 
  ADD COLUMN IF NOT EXISTS released_by UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS released_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS returned_by UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS returned_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS return_condition TEXT CHECK (return_condition IN ('Good', 'Damaged')),
  ADD COLUMN IF NOT EXISTS return_remarks TEXT;

-- Widen text fields on borrowing_requests to TEXT
DO $$
BEGIN
    ALTER TABLE public.borrowing_requests ALTER COLUMN purpose TYPE TEXT;
    ALTER TABLE public.borrowing_requests ALTER COLUMN status TYPE TEXT;
    ALTER TABLE public.borrowing_requests ALTER COLUMN rejection_reason TYPE TEXT;
    ALTER TABLE public.borrowing_requests ALTER COLUMN return_condition TYPE TEXT;
    ALTER TABLE public.borrowing_requests ALTER COLUMN return_remarks TYPE TEXT;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- Enable RLS on borrowing_requests
ALTER TABLE public.borrowing_requests ENABLE ROW LEVEL SECURITY;

-- RLS Policies for borrowing_requests
DROP POLICY IF EXISTS "Users can view relevant borrowing requests" ON public.borrowing_requests;
CREATE POLICY "Users can view relevant borrowing requests"
ON public.borrowing_requests FOR SELECT
TO authenticated
USING (
    requester_id = auth.uid() 
    OR public.get_user_role(auth.uid()) IN ('administrator', 'laboratory_staff')
);

DROP POLICY IF EXISTS "Requesters can insert pending requests" ON public.borrowing_requests;
CREATE POLICY "Requesters can insert pending requests"
ON public.borrowing_requests FOR INSERT
TO authenticated
WITH CHECK (
    requester_id = auth.uid() 
    AND status = 'Pending'
);

DROP POLICY IF EXISTS "Administrators can update borrowing requests" ON public.borrowing_requests;
CREATE POLICY "Administrators can update borrowing requests"
ON public.borrowing_requests FOR UPDATE
TO authenticated
USING (
    public.get_user_role(auth.uid()) = 'administrator'
);

-- =========================================================
-- MAINTENANCE MANAGEMENT TABLE & POLICIES
-- =========================================================

CREATE TABLE IF NOT EXISTS public.maintenance_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    equipment_id UUID NOT NULL REFERENCES public.equipment(id) ON DELETE CASCADE,
    reported_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    issue_description TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('Pending', 'In_Maintenance', 'Completed', 'Cancelled')) DEFAULT 'Pending',
    resolved_by UUID REFERENCES public.profiles(id),
    resolution_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff and Admin view maintenance" ON public.maintenance_requests;
CREATE POLICY "Staff and Admin view maintenance"
ON public.maintenance_requests FOR SELECT
TO authenticated
USING (public.get_user_role(auth.uid()) IN ('administrator', 'laboratory_staff'));

DROP POLICY IF EXISTS "Staff and Admin submit maintenance" ON public.maintenance_requests;
CREATE POLICY "Staff and Admin submit maintenance"
ON public.maintenance_requests FOR INSERT
TO authenticated
WITH CHECK (public.get_user_role(auth.uid()) IN ('administrator', 'laboratory_staff'));

DROP POLICY IF EXISTS "Admin manage maintenance" ON public.maintenance_requests;
CREATE POLICY "Admin manage maintenance"
ON public.maintenance_requests FOR UPDATE
TO authenticated
USING (public.get_user_role(auth.uid()) = 'administrator');

-- =========================================================
-- AUDIT TRAIL SYSTEM TABLE & POLICIES
-- =========================================================

CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    module TEXT NOT NULL,
    record_id TEXT,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Administrators can view audit logs" ON public.audit_logs;
CREATE POLICY "Administrators can view audit logs"
ON public.audit_logs FOR SELECT
TO authenticated
USING (public.get_user_role(auth.uid()) = 'administrator');

DROP POLICY IF EXISTS "Authenticated users can insert audit logs" ON public.audit_logs;
CREATE POLICY "Authenticated users can insert audit logs"
ON public.audit_logs FOR INSERT
TO authenticated
WITH CHECK (true);

-- Logger Helper Function
CREATE OR REPLACE FUNCTION public.log_audit_event(
    p_user_id UUID,
    p_action TEXT,
    p_module TEXT,
    p_record_id TEXT,
    p_description TEXT
) RETURNS VOID AS $$
BEGIN
  INSERT INTO public.audit_logs (user_id, action, module, record_id, description, created_at)
  VALUES (
    COALESCE(p_user_id, auth.uid()),
    p_action,
    p_module,
    p_record_id,
    p_description,
    NOW()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =========================================================
-- SECURE RPC PROCEDURES (BORROWING, MAINTENANCE, USERS, EQUIPMENT)
-- =========================================================

-- RPC: Approve Borrowing Request
CREATE OR REPLACE FUNCTION public.approve_borrowing_request(p_request_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_request RECORD;
  v_equipment RECORD;
  v_admin_role TEXT;
BEGIN
  v_admin_role := public.get_user_role(auth.uid());
  IF v_admin_role <> 'administrator' THEN
    RETURN jsonb_build_object('success', false, 'message', 'BR-A4-03: Only Administrators can approve requests.');
  END IF;

  SELECT * INTO v_request FROM public.borrowing_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Borrowing request not found.');
  END IF;

  IF v_request.requester_id = auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'message', 'BR-A4-02 Violation: Administrators cannot approve their own borrowing request.');
  END IF;

  IF v_request.status <> 'Pending' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Only Pending requests can be approved. Current status: ' || v_request.status);
  END IF;

  SELECT * INTO v_equipment FROM public.equipment WHERE id = v_request.equipment_id;
  IF NOT FOUND OR v_equipment.status <> 'Available' THEN
    RETURN jsonb_build_object('success', false, 'message', 'BR-A4-01 Violation: Equipment is currently unavailable (Status: ' || COALESCE(v_equipment.status, 'Unknown') || ').');
  END IF;

  UPDATE public.borrowing_requests
  SET status = 'Approved',
      approved_by = auth.uid(),
      approved_at = NOW(),
      updated_at = NOW()
  WHERE id = p_request_id;

  PERFORM public.log_audit_event(
    auth.uid(), 'APPROVED', 'Borrowing', p_request_id::text, 
    'Approved borrowing request for item: ' || v_equipment.name
  );

  RETURN jsonb_build_object('success', true, 'message', 'Request approved successfully.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Reject Borrowing Request
CREATE OR REPLACE FUNCTION public.reject_borrowing_request(p_request_id UUID, p_reason TEXT)
RETURNS JSONB AS $$
DECLARE
  v_request RECORD;
  v_admin_role TEXT;
BEGIN
  v_admin_role := public.get_user_role(auth.uid());
  IF v_admin_role <> 'administrator' THEN
    RETURN jsonb_build_object('success', false, 'message', 'BR-A4-03: Only Administrators can reject requests.');
  END IF;

  SELECT * INTO v_request FROM public.borrowing_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Borrowing request not found.');
  END IF;

  IF v_request.status <> 'Pending' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Only Pending requests can be rejected.');
  END IF;

  UPDATE public.borrowing_requests
  SET status = 'Rejected',
      approved_by = auth.uid(),
      rejection_reason = COALESCE(p_reason, 'No reason specified'),
      updated_at = NOW()
  WHERE id = p_request_id;

  PERFORM public.log_audit_event(
    auth.uid(), 'REJECTED', 'Borrowing', p_request_id::text, 
    'Rejected borrowing request. Reason: ' || COALESCE(p_reason, 'No reason specified')
  );

  RETURN jsonb_build_object('success', true, 'message', 'Request rejected successfully.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Release Borrowing Request
CREATE OR REPLACE FUNCTION public.release_borrowing_request(p_request_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_request RECORD;
  v_equipment RECORD;
  v_user_role TEXT;
BEGIN
  v_user_role := public.get_user_role(auth.uid());
  IF v_user_role NOT IN ('administrator', 'laboratory_staff') THEN
    RETURN jsonb_build_object('success', false, 'message', 'Access Denied: Requesters cannot release equipment.');
  END IF;

  SELECT * INTO v_request FROM public.borrowing_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Borrowing request not found.');
  END IF;

  IF v_request.status = 'Rejected' THEN
    RETURN jsonb_build_object('success', false, 'message', 'BR-A4-07 Violation: Rejected requests cannot be released.');
  END IF;

  IF v_request.status <> 'Approved' THEN
    RETURN jsonb_build_object('success', false, 'message', 'BR-A4-04 Violation: Only Approved requests can be released. Current status is ' || v_request.status || '.');
  END IF;

  SELECT * INTO v_equipment FROM public.equipment WHERE id = v_request.equipment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Equipment record not found.');
  END IF;

  IF v_equipment.status = 'Maintenance' THEN
    RETURN jsonb_build_object('success', false, 'message', 'BR-A4-09 Violation: Equipment is under maintenance and cannot be released.');
  END IF;

  IF v_equipment.status <> 'Available' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Equipment is currently unavailable (Status: ' || v_equipment.status || ').');
  END IF;

  UPDATE public.borrowing_requests
  SET status = 'Released',
      released_by = auth.uid(),
      released_at = NOW(),
      updated_at = NOW()
  WHERE id = p_request_id;

  UPDATE public.equipment
  SET status = 'Borrowed'
  WHERE id = v_request.equipment_id;

  PERFORM public.log_audit_event(
    auth.uid(), 'RELEASED', 'Borrowing', p_request_id::text, 
    'Released approved equipment (' || v_equipment.name || ') for borrowing transaction.'
  );

  RETURN jsonb_build_object('success', true, 'message', 'Equipment released successfully. Status updated to Borrowed.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Return Borrowing Request
CREATE OR REPLACE FUNCTION public.return_borrowing_request(
    p_request_id UUID, 
    p_condition TEXT, 
    p_remarks TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_request RECORD;
  v_equipment RECORD;
  v_user_role TEXT;
  v_new_equip_status TEXT;
BEGIN
  v_user_role := public.get_user_role(auth.uid());
  IF v_user_role NOT IN ('administrator', 'laboratory_staff') THEN
    RETURN jsonb_build_object('success', false, 'message', 'Access Denied: Requesters cannot process equipment returns.');
  END IF;

  IF p_condition NOT IN ('Good', 'Damaged') THEN
    RETURN jsonb_build_object('success', false, 'message', 'Invalid return condition specified. Must be Good or Damaged.');
  END IF;

  SELECT * INTO v_request FROM public.borrowing_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Borrowing request not found.');
  END IF;

  IF v_request.status IN ('Returned', 'Closed') THEN
    RETURN jsonb_build_object('success', false, 'message', 'BR-A4-08 Violation: Returned transactions cannot be processed twice.');
  END IF;

  IF v_request.status <> 'Released' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Only Released transactions can be returned. Current status is ' || v_request.status || '.');
  END IF;

  SELECT * INTO v_equipment FROM public.equipment WHERE id = v_request.equipment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Equipment record not found.');
  END IF;

  IF p_condition = 'Good' THEN
    v_new_equip_status := 'Available';
  ELSE
    v_new_equip_status := 'Damaged';
  END IF;

  UPDATE public.borrowing_requests
  SET status = 'Returned',
      returned_by = auth.uid(),
      returned_at = NOW(),
      return_condition = p_condition,
      return_remarks = COALESCE(p_remarks, ''),
      updated_at = NOW()
  WHERE id = p_request_id;

  UPDATE public.equipment
  SET status = v_new_equip_status,
      condition = CASE WHEN p_condition = 'Damaged' THEN 'Damaged' ELSE condition END
  WHERE id = v_request.equipment_id;

  PERFORM public.log_audit_event(
    auth.uid(), 'RETURNED', 'Returns', p_request_id::text, 
    'Processed equipment return. Condition: ' || p_condition || '. Equipment status set to ' || v_new_equip_status
  );

  RETURN jsonb_build_object('success', true, 'message', 'Return processed successfully. Equipment status set to ' || v_new_equip_status || '.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Submit Maintenance Request
CREATE OR REPLACE FUNCTION public.submit_maintenance_request(
    p_equipment_id UUID,
    p_description TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_role TEXT;
  v_equip RECORD;
  v_req_id UUID;
BEGIN
  v_role := public.get_user_role(auth.uid());
  IF v_role <> 'laboratory_staff' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Access Denied: Only Laboratory Staff can submit maintenance requests.');
  END IF;

  SELECT * INTO v_equip FROM public.equipment WHERE id = p_equipment_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Equipment not found.');
  END IF;

  INSERT INTO public.maintenance_requests (equipment_id, reported_by, issue_description, status)
  VALUES (p_equipment_id, auth.uid(), p_description, 'Pending')
  RETURNING id INTO v_req_id;

  PERFORM public.log_audit_event(
    auth.uid(), 'MAINTENANCE_REQUESTED', 'Maintenance', v_req_id::text,
    'Submitted maintenance request for equipment: ' || v_equip.name || '. Issue: ' || p_description
  );

  RETURN jsonb_build_object('success', true, 'message', 'Maintenance request submitted successfully.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Start Equipment Maintenance
CREATE OR REPLACE FUNCTION public.start_equipment_maintenance(p_maintenance_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_role TEXT;
  v_maint RECORD;
BEGIN
  v_role := public.get_user_role(auth.uid());
  IF v_role <> 'administrator' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Access Denied: Only Administrators can manage equipment maintenance.');
  END IF;

  SELECT * INTO v_maint FROM public.maintenance_requests WHERE id = p_maintenance_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Maintenance request not found.');
  END IF;

  UPDATE public.maintenance_requests
  SET status = 'In_Maintenance',
      resolved_by = auth.uid(),
      updated_at = NOW()
  WHERE id = p_maintenance_id;

  UPDATE public.equipment
  SET status = 'Maintenance'
  WHERE id = v_maint.equipment_id;

  PERFORM public.log_audit_event(
    auth.uid(), 'UPDATED', 'Maintenance', p_maintenance_id::text,
    'Started maintenance on equipment ID ' || v_maint.equipment_id
  );

  RETURN jsonb_build_object('success', true, 'message', 'Equipment placed in Maintenance mode.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Complete Equipment Maintenance
CREATE OR REPLACE FUNCTION public.complete_equipment_maintenance(
    p_maintenance_id UUID,
    p_target_status TEXT,
    p_notes TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_role TEXT;
  v_maint RECORD;
BEGIN
  v_role := public.get_user_role(auth.uid());
  IF v_role <> 'administrator' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Access Denied: Only Administrators can complete maintenance.');
  END IF;

  IF p_target_status NOT IN ('Available', 'Unserviceable') THEN
    RETURN jsonb_build_object('success', false, 'message', 'Invalid target status. Must be Available or Unserviceable.');
  END IF;

  SELECT * INTO v_maint FROM public.maintenance_requests WHERE id = p_maintenance_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Maintenance record not found.');
  END IF;

  UPDATE public.maintenance_requests
  SET status = 'Completed',
      resolution_notes = COALESCE(p_notes, 'Maintenance completed'),
      resolved_by = auth.uid(),
      updated_at = NOW()
  WHERE id = p_maintenance_id;

  UPDATE public.equipment
  SET status = p_target_status
  WHERE id = v_maint.equipment_id;

  PERFORM public.log_audit_event(
    auth.uid(), 'UPDATED', 'Maintenance', p_maintenance_id::text,
    'Completed maintenance. Equipment status set to: ' || p_target_status
  );

  RETURN jsonb_build_object('success', true, 'message', 'Maintenance completed successfully. Equipment status set to ' || p_target_status);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Update User Role (User Management)
CREATE OR REPLACE FUNCTION public.update_user_role(
    p_target_user_id UUID,
    p_new_role TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_caller_role TEXT;
  v_target RECORD;
BEGIN
  v_caller_role := public.get_user_role(auth.uid());
  IF v_caller_role <> 'administrator' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Access Denied: Only Administrators can assign user roles.');
  END IF;

  -- Prevent self-role modification
  IF p_target_user_id = auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'message', 'Security Rule: You cannot change your own role.');
  END IF;

  IF p_new_role NOT IN ('administrator', 'laboratory_staff', 'requester') THEN
    RETURN jsonb_build_object('success', false, 'message', 'Invalid role specified.');
  END IF;

  SELECT * INTO v_target FROM public.profiles WHERE id = p_target_user_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'User profile not found.');
  END IF;

  UPDATE public.profiles
  SET role = p_new_role
  WHERE id = p_target_user_id;

  PERFORM public.log_audit_event(
    auth.uid(), 'UPDATED', 'Users', p_target_user_id::text,
    'Updated user role for ' || v_target.email || ' from ' || v_target.role || ' to ' || p_new_role
  );

  RETURN jsonb_build_object('success', true, 'message', 'User role updated successfully to ' || p_new_role);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Create Equipment (Admin Only)
CREATE OR REPLACE FUNCTION public.create_equipment(
    p_code TEXT,
    p_name TEXT,
    p_category TEXT,
    p_quantity INT,
    p_condition TEXT,
    p_laboratory TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_role TEXT;
  v_id UUID;
BEGIN
  v_role := public.get_user_role(auth.uid());
  IF v_role <> 'administrator' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Access Denied: Only Administrators can create equipment.');
  END IF;

  INSERT INTO public.equipment (equipment_code, name, category, quantity, condition, laboratory, status)
  VALUES (p_code, p_name, p_category, GREATEST(1, p_quantity), p_condition, p_laboratory, 'Available')
  RETURNING id INTO v_id;

  PERFORM public.log_audit_event(
    auth.uid(), 'CREATED', 'Equipment', v_id::text,
    'Added new equipment: [' || p_code || '] ' || p_name
  );

  RETURN jsonb_build_object('success', true, 'message', 'Equipment added successfully.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Update Equipment (Admin Only)
CREATE OR REPLACE FUNCTION public.update_equipment(
    p_id UUID,
    p_code TEXT,
    p_name TEXT,
    p_category TEXT,
    p_quantity INT,
    p_condition TEXT,
    p_laboratory TEXT,
    p_status TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_role TEXT;
BEGIN
  v_role := public.get_user_role(auth.uid());
  IF v_role <> 'administrator' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Access Denied: Only Administrators can edit equipment.');
  END IF;

  UPDATE public.equipment
  SET equipment_code = p_code,
      name = p_name,
      category = p_category,
      quantity = GREATEST(1, p_quantity),
      condition = p_condition,
      laboratory = p_laboratory,
      status = p_status
  WHERE id = p_id;

  PERFORM public.log_audit_event(
    auth.uid(), 'UPDATED', 'Equipment', p_id::text,
    'Updated equipment details for: ' || p_name
  );

  RETURN jsonb_build_object('success', true, 'message', 'Equipment updated successfully.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Delete Equipment (Admin Only - Prevents deleting equipment with active borrowings)
CREATE OR REPLACE FUNCTION public.delete_equipment(p_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_role TEXT;
  v_active_count INT;
  v_code TEXT;
BEGIN
  v_role := public.get_user_role(auth.uid());
  IF v_role <> 'administrator' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Access Denied: Only Administrators can delete equipment.');
  END IF;

  SELECT equipment_code INTO v_code FROM public.equipment WHERE id = p_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Equipment not found.');
  END IF;

  SELECT COUNT(*) INTO v_active_count 
  FROM public.borrowing_requests 
  WHERE equipment_id = p_id AND status IN ('Pending', 'Approved', 'Released');

  IF v_active_count > 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'Cannot delete equipment with active pending, approved, or released borrowing transactions.');
  END IF;

  DELETE FROM public.equipment WHERE id = p_id;

  PERFORM public.log_audit_event(
    auth.uid(), 'DELETED', 'Equipment', p_id::text,
    'Deleted equipment: ' || COALESCE(v_code, p_id::text)
  );

  RETURN jsonb_build_object('success', true, 'message', 'Equipment deleted successfully.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
