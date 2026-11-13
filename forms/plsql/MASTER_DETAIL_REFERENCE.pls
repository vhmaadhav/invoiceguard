/* ===========================================================================
   Master-detail coordination code, as Oracle Forms Builder generates it when a
   Relation is created in the GUI. frmxml2f does NOT generate it, so
   gen_forms_xml.py must emit it for every form that has Relations.

   Emit:
     - the three program units below (once per form, in this order:
       CHECK_PACKAGE_FAILURE, QUERY_MASTER_DETAILS, CLEAR_ALL_MASTER_DETAILS)
     - on each MASTER block: an ON-POPULATE-DETAILS trigger and an
       ON-CLEAR-DETAILS trigger (templates at the bottom), with one
       "detail program section" per relation of that master.
   =========================================================================== */

-- ---------------------------------------------------------------------------
-- Program unit: CHECK_PACKAGE_FAILURE   (ProgramUnitType = Procedure)
-- ---------------------------------------------------------------------------
PROCEDURE Check_Package_Failure IS
BEGIN
  IF NOT ( Form_Success ) THEN
    RAISE Form_Trigger_Failure;
  END IF;
END;

-- ---------------------------------------------------------------------------
-- Program unit: QUERY_MASTER_DETAILS   (ProgramUnitType = Procedure)
-- ---------------------------------------------------------------------------
PROCEDURE Query_Master_Details(rel_id Relation, detail VARCHAR2) IS
  oldmsg VARCHAR2(2);
  reldef VARCHAR2(5);
BEGIN
  reldef := Get_Relation_Property(rel_id, DEFERRED_COORDINATION);
  oldmsg := :System.Message_Level;
  IF reldef = 'FALSE' THEN
    Go_Block(detail);
    Check_Package_Failure;
    :System.Message_Level := '10';
    Execute_Query;
    :System.Message_Level := oldmsg;
  ELSE
    Set_Block_Property(detail, COORDINATION_STATUS, NON_COORDINATED);
  END IF;
EXCEPTION
  WHEN Form_Trigger_Failure THEN
    :System.Message_Level := oldmsg;
    RAISE;
END Query_Master_Details;

-- ---------------------------------------------------------------------------
-- Program unit: CLEAR_ALL_MASTER_DETAILS   (ProgramUnitType = Procedure)
-- ---------------------------------------------------------------------------
PROCEDURE Clear_All_Master_Details IS
  mastblk  VARCHAR2(30);
  coordop  VARCHAR2(30);
  trigblk  VARCHAR2(30);
  startitm VARCHAR2(61);
  frmstat  VARCHAR2(15);
  curblk   VARCHAR2(30);
  currel   VARCHAR2(30);
  curdtl   VARCHAR2(30);

  FUNCTION First_Changed_Block_Below(Master VARCHAR2) RETURN VARCHAR2 IS
    curblk VARCHAR2(30);
    currel VARCHAR2(30);
    retblk VARCHAR2(30);
  BEGIN
    curblk := Master;
    currel := Get_Block_Property(curblk, FIRST_MASTER_RELATION);
    WHILE currel IS NOT NULL LOOP
      curblk := Get_Relation_Property(currel, DETAIL_NAME);
      IF ( Get_Block_Property(curblk, STATUS) = 'CHANGED' ) THEN
        RETURN curblk;
      ELSE
        retblk := First_Changed_Block_Below(curblk);
        IF retblk IS NOT NULL THEN
          RETURN retblk;
        ELSE
          currel := Get_Relation_Property(currel, NEXT_MASTER_RELATION);
        END IF;
      END IF;
    END LOOP;
    RETURN NULL;
  END First_Changed_Block_Below;

BEGIN
  mastblk  := :System.Master_Block;
  coordop  := :System.Coordination_Operation;
  trigblk  := :System.Trigger_Block;
  startitm := :System.Cursor_Item;
  frmstat  := :System.Form_Status;

  IF coordop NOT IN ('CLEAR_RECORD', 'SYNCHRONIZE_BLOCKS') THEN
    IF mastblk = trigblk THEN
      IF frmstat = 'CHANGED' THEN
        curblk := First_Changed_Block_Below(mastblk);
        IF curblk IS NOT NULL THEN
          Go_Block(curblk);
          Check_Package_Failure;
          Clear_Block(ASK_COMMIT);
          IF NOT ( :System.Form_Status = 'QUERY'
                   OR :System.Block_Status = 'NEW' ) THEN
            RAISE Form_Trigger_Failure;
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

  currel := Get_Block_Property(trigblk, FIRST_MASTER_RELATION);
  WHILE currel IS NOT NULL LOOP
    curdtl := Get_Relation_Property(currel, DETAIL_NAME);
    IF Get_Block_Property(curdtl, STATUS) <> 'NEW' THEN
      Go_Block(curdtl);
      Check_Package_Failure;
      Clear_Block(NO_VALIDATE);
      IF :System.Block_Status <> 'NEW' THEN
        RAISE Form_Trigger_Failure;
      END IF;
    END IF;
    currel := Get_Relation_Property(currel, NEXT_MASTER_RELATION);
  END LOOP;

  IF :System.Cursor_Item <> startitm THEN
    Go_Item(startitm);
    Check_Package_Failure;
  END IF;
EXCEPTION
  WHEN Form_Trigger_Failure THEN
    IF :System.Cursor_Item <> startitm THEN
      Go_Item(startitm);
    END IF;
    RAISE;
END Clear_All_Master_Details;

-- ---------------------------------------------------------------------------
-- Trigger template: ON-CLEAR-DETAILS   (on the MASTER block)
-- ---------------------------------------------------------------------------
BEGIN
  Clear_All_Master_Details;
END;

-- ---------------------------------------------------------------------------
-- Trigger template: ON-POPULATE-DETAILS   (on the MASTER block)
-- Example for master INV_HDR with relations INV_HDR_INV_LINES, INV_HDR_HOLDS.
-- Find_Relation takes 'MASTERBLOCK.RELATIONNAME'. Repeat the detail section
-- for every relation whose master is this block.
-- ---------------------------------------------------------------------------
DECLARE
  recstat  VARCHAR2(20) := :System.Record_Status;
  startitm VARCHAR2(61) := :System.Cursor_Item;
  rel_id   Relation;
BEGIN
  IF ( recstat = 'NEW' OR recstat = 'INSERT' ) THEN
    RETURN;
  END IF;

  IF ( :INV_HDR.INVOICE_ID IS NOT NULL ) THEN
    rel_id := Find_Relation('INV_HDR.INV_HDR_INV_LINES');
    Query_Master_Details(rel_id, 'INV_LINES');
  END IF;

  IF ( :INV_HDR.INVOICE_ID IS NOT NULL ) THEN
    rel_id := Find_Relation('INV_HDR.INV_HDR_HOLDS');
    Query_Master_Details(rel_id, 'HOLDS');
  END IF;

  IF ( :System.Cursor_Item <> startitm ) THEN
    Go_Item(startitm);
    Check_Package_Failure;
  END IF;
END;
