

--1)  One (1) Stored procedure to insert a new row of data into one of your database tables (the stored procedures must use lookup code for foreign keys.)


-- Drop existing procedure if it exists
IF OBJECT_ID('InsertAuditReport', 'P') IS NOT NULL
    DROP PROCEDURE InsertAuditReport;
GO

-- Create procedure to insert an audit report
CREATE PROCEDURE InsertAuditReport
    @AuditDate DATE,
    @Findings NVARCHAR(255),
    @ProjectName NVARCHAR(50) -- Foreign key reference
AS
BEGIN
    DECLARE @ProjectID INT;
    
    BEGIN TRY
        -- Start transaction
        BEGIN TRANSACTION;
        
        -- Subquery to find the ProjectID based on ProjectName
        SELECT @ProjectID = ProjectID
        FROM Projects
        WHERE ProjectName = @ProjectName;
        
        -- If ProjectID is not found, raise an error and rollback
        IF @ProjectID IS NULL
        BEGIN
            RAISERROR('Project not found for the given ProjectName.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Insert the audit report if ProjectID is valid
        INSERT INTO AuditReports (AuditDate, Findings, ProjectID)
        VALUES (@AuditDate, @Findings, @ProjectID);

        -- Commit transaction
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        -- Rollback transaction on error
        ROLLBACK TRANSACTION;
        
        -- Capture and raise the error message
        DECLARE @ErrorMessage NVARCHAR(4000);
        DECLARE @ErrorSeverity INT;
        DECLARE @ErrorState INT;
        
        SELECT @ErrorMessage = ERROR_MESSAGE(),
               @ErrorSeverity = ERROR_SEVERITY(),
               @ErrorState = ERROR_STATE();
        
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END;
GO


--2)  One (1) Nested stored procedure insert query to insert a new row of data into another of your database tables (the main stored procedures should invoke stored procedures that lookup the applicable foreign keys.)

--  Drop and Create Stored Procedures for Inserting a New Row with Nested Logic
IF OBJECT_ID('InsertInvestigation', 'P') IS NOT NULL
    DROP PROCEDURE InsertInvestigation;
GO

-- Create main procedure for inserting a new investigation
CREATE PROCEDURE InsertInvestigation 
    @StartDate DATE, 
    @EndDate DATE,
    @ProjectName NVARCHAR(100)
AS
BEGIN
    DECLARE @ProjectID INT;

    BEGIN TRY
        -- Start transaction
        BEGIN TRANSACTION;

        -- Invoke nested procedure to get ProjectID
        EXEC GetProjectID @ProjectName, @ProjectID OUTPUT;

        -- Check if ProjectID is valid
        IF @ProjectID IS NULL
        BEGIN
            RAISERROR('Project not found for the given ProjectName.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Check if StartDate is before EndDate (CHECK constraint)
        IF @StartDate >= @EndDate
        BEGIN
            RAISERROR('StartDate must be earlier than EndDate.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Insert a new investigation row if ProjectID is valid
        INSERT INTO Investigation (StartDate, EndDate, ProjectID)
        VALUES (@StartDate, @EndDate, @ProjectID);

        -- Commit transaction
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        -- Rollback transaction on error
        ROLLBACK TRANSACTION;

        -- Capture and raise the error message
        DECLARE @ErrorMessage NVARCHAR(4000);
        DECLARE @ErrorSeverity INT;
        DECLARE @ErrorState INT;
        
        SELECT @ErrorMessage = ERROR_MESSAGE(),
               @ErrorSeverity = ERROR_SEVERITY(),
               @ErrorState = ERROR_STATE();
        
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END;
GO


-- 3) Add a Check Constraint for the Projects Table

BEGIN TRY
    -- Check and drop existing constraint if it exists
    IF EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CHK_BudgetFormat')
    BEGIN
        ALTER TABLE Projects DROP CONSTRAINT CHK_BudgetFormat;
    END
    
    -- Add the Check constraint to ensure valid budget format
    ALTER TABLE Projects
    ADD CONSTRAINT CHK_BudgetFormat
    CHECK (Budget LIKE '$%' AND TRY_CAST(REPLACE(Budget, '$', '') AS DECIMAL(18, 2)) >= 1000);
    
    PRINT 'Check constraint CHK_BudgetFormat added successfully.';
END TRY
BEGIN CATCH
    PRINT 'Error occurred: ' + ERROR_MESSAGE();
END CATCH;
GO






-- 4)One (1) Computed column
-- Create a user-defined function to convert an amount from a VARCHAR data type to a DECIMAL

-- Step 1: Drop the computed column in the Funding table if it exists
IF COL_LENGTH('Funding', 'TotalAmount') IS NOT NULL
BEGIN
    ALTER TABLE Funding DROP COLUMN TotalAmount;
END
GO

-- Step 2: Drop the existing function if it exists
IF OBJECT_ID('ConvertAmountToDecimal', 'FN') IS NOT NULL
    DROP FUNCTION ConvertAmountToDecimal;
GO

-- Step 3: Create the function to convert Amount from VARCHAR to DECIMAL
CREATE FUNCTION ConvertAmountToDecimal (@Amount VARCHAR(11))
RETURNS DECIMAL(18, 2)
AS
BEGIN
    -- Remove the dollar sign and convert to DECIMAL
    RETURN CAST(REPLACE(@Amount, '$', '') AS DECIMAL(18, 2));
END;
GO

-- Step 4: Add the computed column back to the Funding table
ALTER TABLE Funding
ADD TotalAmount AS dbo.ConvertAmountToDecimal(Amount);
GO

-- Step 5: Drop the existing view if it exists
IF OBJECT_ID('vw_FundingSummary', 'V') IS NOT NULL
    DROP VIEW vw_FundingSummary;
GO

-- Step 6: Create a complex view with JOINs, GROUP BY, ORDER BY, and RANK
CREATE VIEW vw_FundingSummary AS
SELECT 
    F.FundingID,
    P.ProjectName,
    dbo.ConvertAmountToDecimal(F.Amount) AS TotalAmount,
    RANK() OVER (ORDER BY dbo.ConvertAmountToDecimal(F.Amount) DESC) AS RankByAmount
FROM 
    Funding F
    JOIN Projects P ON F.ProjectID = P.ProjectID
WHERE 
    dbo.ConvertAmountToDecimal(F.Amount) > 1000000;
GO

-- Step 7: Verify the computed column and view
SELECT FundingID, Amount, TotalAmount FROM Funding;
SELECT * FROM vw_FundingSummary;










